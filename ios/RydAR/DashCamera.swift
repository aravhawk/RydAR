import AVFoundation
import CoreImage
import CoreML
import CoreVideo
import Vision

enum DashModelError: Error {
    case missingPackage
    case unreadable
}

/// Opens the camera only after a Dash trip starts and the driver gate allows it.
/// Creating one does not load the model. Frames are not written anywhere.
final class DashCamera: NSObject, DashRunning, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onChange: ((DashReading) -> Void)?
    var loader: () throws -> VNCoreMLModel
    var thermal: () -> Bool
    private(set) var didLoadModel = false

    private let queue = DispatchQueue(label: "com.rydar.dash")
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private var session: AVCaptureSession?
    private var request: VNCoreMLRequest?
    private var windows = DashWindows()
    private var clock = DashClock()
    private var running = false
    private var surface: RoadSurface?
    private let surfaceLock = NSLock()
    private let previewLock = NSLock()
    private var previewStorage: AVCaptureSession?

    /// Read from the main thread. The session itself is only started and stopped on the camera queue.
    var previewSession: AVCaptureSession? {
        previewLock.lock()
        defer { previewLock.unlock() }
        return previewStorage
    }

    private func setPreview(_ capture: AVCaptureSession?) {
        previewLock.lock()
        previewStorage = capture
        previewLock.unlock()
    }

    init(
        loader: @escaping () throws -> VNCoreMLModel = DashCamera.loadBundled,
        thermal: @escaping () -> Bool = DashThermal.isSerious
    ) {
        self.loader = loader
        self.thermal = thermal
    }

    static func loadBundled() throws -> VNCoreMLModel {
        guard let url = Bundle.main.url(forResource: "RoadSurface", withExtension: "mlmodelc") else {
            throw DashModelError.missingPackage
        }
        let model = try MLModel(contentsOf: url)
        let names = Set(model.modelDescription.outputDescriptionsByName.keys)
        guard names.isSuperset(of: ["material", "friction", "uneven"]) else {
            throw DashModelError.unreadable
        }
        return try VNCoreMLModel(for: model)
    }

    func noteMatchedSurface(_ surface: RoadSurface?) {
        surfaceLock.lock()
        self.surface = surface
        surfaceLock.unlock()
    }

    func noteCurveApproach(_ curveID: String?) {
        queue.async { [weak self] in
            self?.windows.noteCurveApproach(curveID)
        }
    }

    func noteCurvePassed(_ curveID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.windows.noteCurvePassed(curveID) else { return }
            guard self.running else { return }
            self.publishCurrent(.running)
        }
    }

    func start() {
        if thermal() {
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.session?.stopRunning()
            self.session = nil
            self.setPreview(nil)
            self.request = nil
            self.windows = DashWindows()
            self.clock = DashClock()
            self.didLoadModel = false
        }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.session?.stopRunning()
            // A reading from before the stop says nothing about the road after it.
            self.windows = DashWindows()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if thermal() {
            running = false
            windows = DashWindows()
            let capture = session
            DispatchQueue.global(qos: .userInitiated).async {
                capture?.stopRunning()
            }
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        guard running, clock.allow(Date()), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let request, let patch = roadBuffer(from: pixelBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: patch, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else { return }
        var heads: [String: [Float]] = [:]
        for observation in observations {
            heads[observation.featureName] = probabilities(observation)
        }
        guard let material = heads["material"], let friction = heads["friction"], let uneven = heads["uneven"] else { return }
        let votes = windows.observe(material: material, friction: friction, uneven: uneven)
        publish(.running, material: votes.0, friction: votes.1, uneven: votes.2)
    }

    private func startOnQueue() {
        if running { return }
        if session != nil {
            session?.startRunning()
            running = true
            publishCurrent(.running)
            return
        }
        let model: VNCoreMLModel
        do {
            model = try loader()
            didLoadModel = true
        } catch {
            didLoadModel = false
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        let visionRequest = VNCoreMLRequest(model: model)
        visionRequest.imageCropAndScaleOption = .scaleFill
        request = visionRequest
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.queue.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
                    }
                }
            }
        default:
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
        }
    }

    private func configureSession() {
        guard session == nil else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        let capture = AVCaptureSession()
        capture.beginConfiguration()
        if capture.canSetSessionPreset(.hd1280x720) {
            capture.sessionPreset = .hd1280x720
        }
        guard capture.canAddInput(input) else {
            capture.commitConfiguration()
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        capture.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard capture.canAddOutput(output) else {
            capture.commitConfiguration()
            publish(.unconfirmed, material: nil, friction: nil, uneven: nil)
            return
        }
        capture.addOutput(output)
        capture.commitConfiguration()
        session = capture
        setPreview(capture)
        capture.startRunning()
        running = true
        publishCurrent(.running)
    }

    private func publishCurrent(_ state: DashCameraState) {
        publish(
            state,
            material: windows.material.accepted(),
            friction: windows.friction.accepted(),
            uneven: windows.uneven.accepted()
        )
    }

    private func roadBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Buffers arrive in the sensor's landscape orientation. `.right` makes them upright portrait,
        // so the lower-center crop is the road under the car. Do not also rotate the capture connection.
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let crop = DashCrop.road(in: oriented.extent)
        let image = oriented.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let width = Int(crop.width.rounded())
        let height = Int(crop.height.rounded())
        guard width > 1, height > 1 else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &output) == kCVReturnSuccess,
              let output else { return nil }
        context.render(image, to: output)
        return output
    }

    private func probabilities(_ observation: VNCoreMLFeatureValueObservation) -> [Float]? {
        guard let array = observation.featureValue.multiArrayValue else { return nil }
        return (0..<array.count).map { array[$0].floatValue }
    }

    private func matchedSurface() -> RoadSurface? {
        surfaceLock.lock()
        defer { surfaceLock.unlock() }
        return surface
    }

    private func publish(_ state: DashCameraState, material: DashVote?, friction: DashVote?, uneven: DashVote?) {
        let reading = dashReading(
            material: material,
            friction: friction,
            uneven: uneven,
            fileSurface: matchedSurface(),
            state: state,
            acceptedAt: Date()
        )
        let callback = onChange
        DispatchQueue.main.async {
            callback?(reading)
        }
    }
}

enum DashThermal {
    static func isSerious() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }
}
