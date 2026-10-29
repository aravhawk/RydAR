import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.appearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @AppStorage(UnitSystem.key) private var units = UnitSystem.imperial.rawValue
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var prompt: SettingsPrompt?
    @State private var showPrompt = false

    private func ask(_ next: SettingsPrompt) {
        prompt = next
        showPrompt = true
    }

    /// Puts the switches back. Settings reset keeps a tire answer so this screen stays up.
    /// Clearing the answer would replace the whole app with the tire check.
    private func applyDefaults(clearTread: Bool) {
        appearance = AppearancePreference.system.rawValue
        units = UnitSystem.imperial.rawValue
        uploadOptIn = true
        dashEnabled = true
        if clearTread {
            TreadStore.clear()
            treadRaw = ""
        } else {
            TreadStore.save(.unsure)
            treadRaw = TreadChoice.unsure.rawValue
        }
        trip.onUploadPreference?(true)
    }

    private func deleteEverything() {
        do {
            try trip.deleteAllData()
            applyDefaults(clearTread: true)
            onboarded = false
        } catch {
            let message = error.localizedDescription
            trip.onUploadPreference?(uploadOptIn)
            DispatchQueue.main.async { ask(.failed(message)) }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { choice in
                        Text(choice.rawValue).tag(choice.rawValue)
                    }
                }
                .accessibilityIdentifier("appearance")
            } header: {
                Text("Appearance")
                    .textCase(nil)
            }

            Section {
                Toggle("Use metric", isOn: Binding(
                    get: { units == UnitSystem.metric.rawValue },
                    set: { units = ($0 ? UnitSystem.metric : UnitSystem.imperial).rawValue }
                ))
                .accessibilityIdentifier("metricUnits")
            } header: {
                Text("Units")
                    .textCase(nil)
            } footer: {
                Text(units == UnitSystem.metric.rawValue ? "Kilometers per hour and meters." : "Miles per hour and feet.")
            }

            Section {
                Toggle("Share anonymous curve data", isOn: $uploadOptIn)
                    .accessibilityIdentifier("settingsUpload")
            } header: {
                Text("Privacy")
                    .textCase(nil)
            } footer: {
                Text("Sends the curve, direction, speed, and hour. Never your name or route.")
            }

            Section {
                Picker("Tire tread", selection: Binding(
                    get: { treadRaw.isEmpty ? TreadChoice.unsure.rawValue : treadRaw },
                    set: { newValue in
                        treadRaw = newValue
                        if let choice = TreadChoice(rawValue: newValue) { TreadStore.save(choice) }
                    }
                )) {
                    ForEach(TreadChoice.allCases) { choice in
                        Text("\(choice.rawValue) · \(choice.detail)").tag(choice.rawValue)
                    }
                }
                .accessibilityIdentifier("treadSetting")
                Toggle("Camera check", isOn: $dashEnabled)
                    .accessibilityIdentifier("dashMode")
            } header: {
                Text("Trips")
                    .textCase(nil)
            } footer: {
                Text("Mount the phone with the camera facing the road, or turn this off. It spots gravel on roads listed as paved.")
            }

            Section {
                Button("Reset all settings", role: .destructive) { ask(.resetSettings) }
                    .accessibilityIdentifier("resetSettings")
                Button("Reset all data", role: .destructive) { ask(.deleteData) }
                    .accessibilityIdentifier("deleteAllData")
            } header: {
                Text("On this iPhone")
                    .textCase(nil)
            } footer: {
                Text("Reset all settings keeps your trips. Reset all data deletes trips and history and starts RydAR over. Road data stays. Roads: Arkansas GIS Office.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        // One alert. Two confirmation dialogs on this form open as a small popover
        // whose confirm button does not receive taps, and neither one offers Cancel.
        .alert(
            prompt?.title ?? "",
            isPresented: $showPrompt,
            presenting: prompt
        ) { prompt in
            switch prompt {
            case .resetSettings:
                Button("Reset all settings", role: .destructive) { applyDefaults(clearTread: false) }
                Button("Cancel", role: .cancel) {}
            case .deleteData:
                Button("Reset all data", role: .destructive) { deleteEverything() }
                Button("Cancel", role: .cancel) {}
            case .failed:
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}

private enum SettingsPrompt: Identifiable {
    case resetSettings
    case deleteData
    case failed(String)

    var id: String {
        switch self {
        case .resetSettings: return "settings"
        case .deleteData: return "data"
        case .failed: return "failed"
        }
    }

    var title: String {
        switch self {
        case .resetSettings: return "Reset all settings?"
        case .deleteData: return "Reset all data?"
        case .failed: return "Could not finish resetting data"
        }
    }

    var message: String {
        switch self {
        case .resetSettings:
            return "Appearance, units, sharing, camera check, and tires go back to their defaults. Your trips stay."
        case .deleteData:
            return "Trips and history are deleted for good. RydAR starts over."
        case .failed(let message):
            return message
        }
    }
}
