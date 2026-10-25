import SwiftUI

struct DriveScreen: View {
    @ObservedObject var trip: TripScreenBridge
    var onFinish: () -> Void
    @State private var confirmParked = false
    private var soundAllowed: Bool { trip.driverMode.map(allowsInDriveSound) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                AuditEyebrow(text: trip.drive.isPaused ? "Trip paused" : trip.drive.tripTitle)
                Spacer()
                Image(systemName: soundAllowed ? "speaker.wave.2" : "speaker.slash")
                    .accessibilityLabel(soundAllowed ? "Sound permitted by driver choice" : "Sound disabled")
            }
            Text(trip.driverMode?.screenTitle ?? "No driver selected").font(.headline)
            Spacer(minLength: 0)
            if !soundAllowed {
                Image(systemName: "moon.zzz.fill").font(.system(size: 52)).foregroundStyle(AuditTheme.accent)
                Text("Put the phone away.").font(.largeTitle.bold())
                Text("Preview before moving. Review after parking. No in-drive sound, camera, or upload.")
                    .foregroundStyle(.secondary)
            } else if trip.drive.isPaused {
                Text("Paused").font(.system(.largeTitle, design: .rounded).bold())
                Text("Prompts and camera are paused.").foregroundStyle(.secondary)
            } else {
                Text("NEXT CURVE").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                if let distance = trip.drive.distanceMeters, distance.isFinite, distance >= 0 {
                    Text(distance.formatted(.number.precision(.fractionLength(0))) + " m")
                        .font(.system(size: 64, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("nextCurveDistance")
                } else {
                    Text("— m").font(.system(size: 64, weight: .bold, design: .rounded))
                }
                Text(trip.drive.nextCurve?.roadName
                     ?? (trip.drive.gpsStatus == "GPS ready" ? "No filed curve ahead" : "Waiting for a matched curve"))
                    .font(.title2.weight(.semibold))
                if let curve = trip.drive.nextCurve {
                    SurfaceBadge(fileSurface: curve.surface, camera: trip.drive.cameraEvidence,
                                 threshold: trip.drive.cameraThreshold)
                    if let range = trip.drive.screeningRange {
                        ScreeningRangeLabel(range: range)
                    }
                } else {
                    Label("Surface unconfirmed", systemImage: "road.lanes").foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    if let mph = trip.drive.measuredSpeedMPH {
                        Text("\(mph, specifier: "%.0f") mph")
                            .font(.title3.monospacedDigit().bold())
                            .accessibilityIdentifier("measuredSpeed")
                        Text("measured").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Speed unknown").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(trip.drive.gpsStatus, systemImage: "location")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let measured = trip.drive.measuredSpeedMPH,
                   let prompt = trip.drive.promptSpeedMPH,
                   measured - prompt > 3 {
                    Text("GPS speed is uncertain. A prompt uses the cautious reading, \(prompt, specifier: "%.0f") mph.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            AuditCard {
                Label(soundAllowed && !trip.drive.isPaused ? trip.drive.cameraStatus : "Off · driver gate or pause",
                      systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                Text("experimental — validated on public datasets only, not on Arkansas roads.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !trip.isConnected {
                Text("UI preview · trip engine unavailable. No recording or prompts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                trip.setPaused(!trip.drive.isPaused)
            } label: {
                Label(trip.drive.isPaused ? "Resume" : "Pause",
                      systemImage: trip.drive.isPaused ? "play.fill" : "pause.fill")
                    .frame(minHeight: 20)
            }
            .buttonStyle(AuditPrimaryButton()).accessibilityIdentifier("pauseTrip")
            if trip.drive.isPaused {
                Button("I'm parked · end trip") { confirmParked = true }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("endTrip")
            }
        }
        .padding(24).background(AuditTheme.background)
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Review only after the vehicle is parked", isPresented: $confirmParked, titleVisibility: .visible) {
            Button("Vehicle is parked · show debrief", action: onFinish)
        }
    }
}
