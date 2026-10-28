import SwiftUI

struct DriveScreen: View {
    @ObservedObject var trip: TripScreenBridge
    var onFinish: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 64
    private var soundAllowed: Bool { trip.driverMode.map(allowsInDriveSound) ?? false }
    private var audioOnly: Bool { trip.driverMode == .under18 }
    private var showsMap: Bool { soundAllowed && !audioOnly && !trip.drive.isPaused }
    /// Curve name, or the rider's place while stopped. A stop does not repeat "Standing still".
    private var readout: DriveReadout {
        driveReadout(
            hasCurve: trip.drive.nextCurve != nil,
            roadName: trip.drive.nextCurve?.roadName,
            gpsStatus: trip.drive.gpsStatus,
            measuredSpeedMPH: trip.drive.measuredSpeedMPH,
            placeTitle: trip.drive.placeTitle,
            placeDetail: trip.drive.placeDetail
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                RydarEyebrow(text: trip.drive.isPaused ? "Trip paused" : trip.drive.tripTitle)
                Spacer()
                Image(systemName: soundAllowed ? "speaker.wave.2" : "speaker.slash")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(soundAllowed ? "Sound on" : "Sound off")
            }
            if showsMap, let latitude = trip.drive.latitude, let longitude = trip.drive.longitude {
                DriveGlanceMap(latitude: latitude, longitude: longitude)
            }
            if audioOnly || !soundAllowed {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(RydarTheme.accent)
                Text("Put the phone away.")
                    .font(.largeTitle.bold())
                Text(trip.drive.isPaused ? "Warnings paused." : "Warnings are on.")
                    .font(.title2.weight(.semibold))
            } else if trip.drive.isPaused {
                Text("Paused")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text("Warnings paused.")
                    .foregroundStyle(.secondary)
            } else {
                RydarEyebrow(text: "Next curve")
                if let distance = trip.drive.distanceMeters, distance.isFinite, distance >= 0 {
                    let shown = distanceText(meters: distance)
                    Text(shown)
                        .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(shown)
                        .accessibilityIdentifier("nextCurveDistance")
                } else {
                    Text("—")
                        .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                        .accessibilityLabel("Distance unknown")
                }
                Text(readout.headline)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("driveHeadline")
                if let notice = trip.drive.advisoryNotice {
                    let warning = trip.drive.advisoryWarning ?? false
                    Text(notice)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(warning ? RydarTheme.warningText : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("advisorySpeed")
                }
                if let curve = trip.drive.nextCurve {
                    SurfaceBadge(fileSurface: curve.surface, camera: trip.drive.cameraEvidence,
                                 threshold: trip.drive.cameraThreshold)
                    if let range = trip.drive.screeningRange {
                        ScreeningRangeLabel(range: range)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    if let mph = readout.speedMPH {
                        Text(speedText(mph: mph))
                            .font(.title3.monospacedDigit().bold())
                            .accessibilityIdentifier("measuredSpeed")
                        Text("now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Speed unknown")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pin = readout.locationPin, pin != trip.drive.gpsStatus {
                        Label(pin, systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.monochrome)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .accessibilityIdentifier("riderLocation")
                    }
                }
                if let measured = trip.drive.measuredSpeedMPH,
                   let prompt = trip.drive.promptSpeedMPH,
                   measured - prompt > 3 {
                    Text("GPS speed is shaky. Using \(speedText(mph: prompt)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !audioOnly {
                RydarCard {
                    DashCameraCard(
                        status: soundAllowed && !trip.drive.isPaused ? trip.drive.cameraStatus : "Camera off",
                        session: trip.cameraPreview,
                        camera: trip.drive.cameraEvidence,
                        live: trip.drive.cameraRunning
                    )
                }
            }
            RydarGlassGroup(spacing: 12) {
                VStack(spacing: 12) {
                    Button {
                        trip.setPaused(!trip.drive.isPaused)
                    } label: {
                        Label(trip.drive.isPaused ? "Resume" : "Pause",
                              systemImage: trip.drive.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .rydarProminentAction()
                    .accessibilityIdentifier("pauseTrip")
                    if trip.drive.isPaused {
                        Button(action: onFinish) {
                            Text("I'm parked · end trip")
                                .frame(maxWidth: .infinity)
                        }
                        .rydarGlassAction()
                        .accessibilityIdentifier("endTrip")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
