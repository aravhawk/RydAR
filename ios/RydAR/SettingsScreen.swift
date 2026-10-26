import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.appearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("rydar.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var confirmResetSettings = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    /// Chime never speaks. Short and Normal both use the one contract sentence.
    private var promptFooter: String {
        if PromptStyle(rawValue: promptStyle) == .chimeOnly {
            return "A chime and a tap."
        }
        return "“\(spokenWarning)” Plus a tap."
    }

    /// Every switch back to its first-launch value. Trips and history are not touched.
    private func resetSettings() {
        appearance = AppearancePreference.system.rawValue
        promptStyle = PromptStyle.normal.rawValue
        uploadOptIn = true
        dashEnabled = true
        TreadStore.clear()
        treadRaw = ""
        trip.onUploadPreference?(true)
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
                Picker("Prompt style", selection: $promptStyle) {
                    ForEach(PromptStyle.allCases) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("promptStyle")
            } header: {
                Text("Hands-free prompts")
                    .textCase(nil)
            } footer: {
                Text(promptFooter)
            }

            Section {
                Toggle("Anonymous pass uploads", isOn: $uploadOptIn)
                    .accessibilityIdentifier("settingsUpload")
            } header: {
                Text("Privacy")
                    .textCase(nil)
            } footer: {
                Text("Helps counties find the curves that need fixing. Curve, direction, 5 mph band, hour. No name or route. Published after 20. Off under 18.")
            }

            Section {
                Picker("Tires", selection: Binding(
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
                Toggle("Dash mode", isOn: $dashEnabled)
                    .accessibilityIdentifier("dashMode")
            } header: {
                Text("Trip setup")
                    .textCase(nil)
            } footer: {
                Text("Paved can only be read as unpaved. Off under 18.")
            }

            Section {
                Button("Reset all settings", role: .destructive) { confirmResetSettings = true }
                    .accessibilityIdentifier("resetSettings")
                Button("Reset all data", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteAllData")
            } header: {
                Text("On this iPhone")
                    .textCase(nil)
            } footer: {
                Text("Settings puts every switch back to its default and keeps your trips. Data also deletes trips, history, and saved copies, and starts RydAR over like a first launch. Roads stay.")
            }

            Section {
                Text("Roads: Arkansas GIS Office.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        .confirmationDialog("Reset all settings?", isPresented: $confirmResetSettings, titleVisibility: .visible) {
            Button("Reset all settings", role: .destructive) { resetSettings() }
        } message: { Text("Appearance, prompts, uploads, Dash, and tires go back to their defaults. Your trips stay.") }
        .confirmationDialog("Reset all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Reset all data", role: .destructive) {
                do {
                    try trip.deleteAllData()
                    try LocalTripExport.deleteAll()
                    resetSettings()
                    onboarded = false
                } catch {
                    deleteError = error.localizedDescription
                    trip.onUploadPreference?(uploadOptIn)
                }
            }
        } message: { Text("Trips, history, and saved copies are deleted and cannot be recovered. RydAR starts over.") }
        .alert("Could not finish resetting data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}
