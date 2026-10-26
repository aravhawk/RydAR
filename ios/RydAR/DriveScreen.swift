import SwiftUI

struct DriveScreen: View {
    @ObservedObject var trip: TripScreenBridge
    var onFinish: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 64
    private var soundAllowed: Bool { trip.driverMode.map(allowsInDriveSound) ?? false }
    /// GPS ready with no filed curve is the matched state. Every other banner is the location status.
    private var unmatchedCurveStatus: String {
        trip.drive.gpsStatus == "GPS ready" ? "No filed curve ahead" : trip.drive.gpsStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                AuditEyebrow(text: trip.drive.isPaused ? "Trip paused" : trip.drive.tripTitle)
                Spacer()
                Image(systemName: soundAllowed ? "speaker.wave.2" : "speaker.slash")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(soundAllowed ? "Sound on" : "Sound off")
            }
            Text(trip.driverMode?.screenTitle ?? "No driver selected")
                .font(.headline)
            Spacer(minLength: 0)
            if !soundAllowed {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AuditTheme.accent)
                Text("Put the phone away.")
                    .font(.largeTitle.bold())
                Text(trip.drive.gpsStatus)
                    .font(.title2.weight(.semibold))
                Text("No voice, camera, or upload.")
                    .foregroundStyle(.secondary)
            } else if trip.drive.isPaused {
                Text("Paused")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text("Alerts paused.")
                    .foregroundStyle(.secondary)
            } else {
                AuditEyebrow(text: "Next curve")
                if let distance = trip.drive.distanceMeters, distance.isFinite, distance >= 0 {
                    let meters = distance.formatted(.number.precision(.fractionLength(0)))
                    Text(meters + " m")
                        .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("\(meters) meters")
                        .accessibilityIdentifier("nextCurveDistance")
                } else {
                    Text("— m")
                        .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                        .accessibilityLabel("Distance unknown")
                }
                Text(trip.drive.nextCurve?.roadName ?? unmatchedCurveStatus)
                    .font(.title2.weight(.semibold))
                if let notice = trip.drive.advisoryNotice {
                    let warning = notice.hasPrefix("Slow") || notice.hasPrefix("Curves")
                    Text(notice)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(warning ? AuditTheme.warningText : .primary)
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
                    if let mph = trip.drive.measuredSpeedMPH {
                        Text("\(mph, specifier: "%.0f") mph")
                            .font(.title3.monospacedDigit().bold())
                            .accessibilityIdentifier("measuredSpeed")
                        Text("measured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Speed unknown")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(trip.drive.gpsStatus, systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.monochrome)
                }
                if let measured = trip.drive.measuredSpeedMPH,
                   let prompt = trip.drive.promptSpeedMPH,
                   measured - prompt > 3 {
                    Text("GPS uncertain. Prompt uses \(prompt, specifier: "%.0f") mph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            AuditCard {
                Label(soundAllowed && !trip.drive.isPaused ? trip.drive.cameraStatus : "Camera off",
                      systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
            }
            if !trip.isConnected {
                Text("Not recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .padding(24)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
