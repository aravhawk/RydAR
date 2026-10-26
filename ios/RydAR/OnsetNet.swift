import Foundation

/// A phone-local network that predicts braking-onset distance in meters.
/// One hidden layer of four tanh units and one linear unit. Inputs are scaled
/// to roughly [-1, 1]: speed / 30, radius feet / 600, paved 1 or 0, night 1 or 0.
/// The linear unit is a correction added to the physics look-ahead. Its learned
/// weights start at zero, so an untrained network predicts on time and the
/// warning does not move. Updates pull back toward those weights.
struct OnsetNet: Equatable {
    static let minimumSamples = 8
    static let learningRate = 0.015
    static let anchorPull = 0.05

    var hiddenWeights: [[Double]]
    var hiddenBias: [Double]
    var outputWeights: [Double]
    var outputBias: Double
    var sampleCount: Int

    static var initial: OnsetNet {
        OnsetNet(
            hiddenWeights: [
                [0.15, 0.04, 0.03, 0.02],
                [0.05, -0.14, 0.04, -0.03],
                [-0.04, 0.05, 0.13, 0.03],
                [0.03, -0.02, -0.05, 0.12],
            ],
            hiddenBias: [0, 0, 0, 0],
            outputWeights: [0, 0, 0, 0],
            outputBias: 0,
            sampleCount: 0
        )
    }

    var canPlaceWarning: Bool { sampleCount >= Self.minimumSamples }

    /// Predicted meters from the curve to the braking start. Untrained, this is
    /// the physics distance for the same speed.
    func predictMeters(speedMps: Double, radiusFeet: Double, paved: Bool, night: Bool) -> Double {
        let speed = speedMps.isFinite ? max(0, speedMps) : 0
        let radius = radiusFeet.isFinite ? max(0, radiusFeet) : 0
        let base = baseLookAheadMeters(speedMps: speed)
        guard hasShape else { return base }
        let correction = linearCorrection(features(speedMps: speed, radiusFeet: radius, paved: paved, night: night))
        guard correction.isFinite else { return base }
        return base + correction
    }

    /// One squared-error step toward a measured braking distance. Nil distances
    /// are not passed in. The step also pulls each weight toward its on-time start.
    mutating func learn(speedMps: Double, radiusFeet: Double, paved: Bool, night: Bool, measuredMeters: Double) {
        guard measuredMeters.isFinite, hasShape else { return }
        let speed = speedMps.isFinite ? max(0, speedMps) : 0
        let radius = radiusFeet.isFinite ? max(0, radiusFeet) : 0
        let x = features(speedMps: speed, radiusFeet: radius, paved: paved, night: night)
        let hidden = activations(for: x)
        let correction = linearCorrection(x, hidden: hidden)
        guard correction.isFinite else { return }
        let predicted = baseLookAheadMeters(speedMps: speed) + correction
        let error = predicted - measuredMeters
        let anchor = OnsetNet.initial
        let rate = Self.learningRate
        let pull = Self.anchorPull

        var nextOutputWeights = outputWeights
        var nextHiddenBias = hiddenBias
        var nextHiddenWeights = hiddenWeights
        let nextOutputBias = outputBias - rate * (error + pull * (outputBias - anchor.outputBias))
        var slope = [Double](repeating: 0, count: 4)
        for i in 0..<4 {
            let activity = hidden[i]
            slope[i] = error * outputWeights[i] * (1 - activity * activity)
            nextOutputWeights[i] = outputWeights[i] - rate * (error * activity + pull * (outputWeights[i] - anchor.outputWeights[i]))
        }
        for i in 0..<4 {
            nextHiddenBias[i] = hiddenBias[i] - rate * (slope[i] + pull * (hiddenBias[i] - anchor.hiddenBias[i]))
            for j in 0..<4 {
                let anchored = hiddenWeights[i][j] - anchor.hiddenWeights[i][j]
                nextHiddenWeights[i][j] = hiddenWeights[i][j] - rate * (slope[i] * x[j] + pull * anchored)
            }
        }
        outputBias = nextOutputBias
        outputWeights = nextOutputWeights
        hiddenBias = nextHiddenBias
        hiddenWeights = nextHiddenWeights
        sampleCount += 1
    }

    func weightRecord() -> (weights: String, bias: String) {
        var weights: [Double] = []
        for row in hiddenWeights {
            weights.append(contentsOf: row)
        }
        weights.append(contentsOf: outputWeights)
        var bias = hiddenBias
        bias.append(outputBias)
        return (Self.encode(weights), Self.encode(bias))
    }

    static func restored(sampleCount: Int, weights: String, bias: String) -> OnsetNet? {
        guard sampleCount >= 0,
              let flat = decode(weights), flat.count == 20,
              let biases = decode(bias), biases.count == 5 else { return nil }
        var rows: [[Double]] = []
        for index in 0..<4 {
            rows.append(Array(flat[(index * 4)..<((index + 1) * 4)]))
        }
        return OnsetNet(
            hiddenWeights: rows,
            hiddenBias: Array(biases[0..<4]),
            outputWeights: Array(flat[16..<20]),
            outputBias: biases[4],
            sampleCount: sampleCount
        )
    }

    private var hasShape: Bool {
        hiddenBias.count == 4 && outputWeights.count == 4 && hiddenWeights.count == 4
            && hiddenWeights.allSatisfy { $0.count == 4 }
    }

    private func features(speedMps: Double, radiusFeet: Double, paved: Bool, night: Bool) -> [Double] {
        [speedMps / 30, radiusFeet / 600, paved ? 1 : 0, night ? 1 : 0]
    }

    private func activations(for x: [Double]) -> [Double] {
        var hidden: [Double] = []
        hidden.reserveCapacity(4)
        for i in 0..<4 {
            var sum = hiddenBias[i]
            for j in 0..<4 {
                sum += hiddenWeights[i][j] * x[j]
            }
            hidden.append(tanh(sum))
        }
        return hidden
    }

    private func linearCorrection(_ x: [Double], hidden: [Double]? = nil) -> Double {
        let activity = hidden ?? activations(for: x)
        var value = outputBias
        for i in 0..<4 {
            value += outputWeights[i] * activity[i]
        }
        return value
    }

    private static func encode(_ values: [Double]) -> String {
        values.map { String($0.bitPattern) }.joined(separator: ",")
    }

    private static func decode(_ text: String) -> [Double]? {
        let parts = text.split(separator: ",")
        var values: [Double] = []
        values.reserveCapacity(parts.count)
        for part in parts {
            guard let bits = UInt64(part) else { return nil }
            values.append(Double(bitPattern: bits))
        }
        return values
    }
}

/// Midpoint of a radius band, in feet. Used when a stored pass has no radius.
func radiusBandCenterFeet(_ band: String) -> Double {
    switch band {
    case "under-150":
        return 75
    case "300-600":
        return 450
    default:
        return 225
    }
}
