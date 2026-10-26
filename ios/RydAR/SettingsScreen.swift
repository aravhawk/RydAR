import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.appearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("rydar.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var confirmDelete = false
    @State private var deleteError: String?

    /// Chime never speaks. Short and Normal both use the one contract sentence.
    private var promptFooter: String {
        if PromptStyle(rawValue: promptStyle) == .chimeOnly {
            return "A chime and a tap."
        }
        return "“\(spokenWarning)” Plus a tap."
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
                Text("Curve, direction, 5 mph band, hour. No name or route. Published after 20. Off under 18.")
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
                Button("Delete all data", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteAllData")
            } header: {
                Text("On this iPhone")
                    .textCase(nil)
            } footer: {
                Text("Trips on this iPhone. Roads stay.")
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
        .confirmationDialog("Delete all local data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                uploadOptIn = true
                dashEnabled = true
                do {
                    try trip.deleteAllData()
                    try LocalTripExport.deleteAll()
                    promptStyle = PromptStyle.normal.rawValue
                    onboarded = false
                    TreadStore.clear()
                    treadRaw = ""
                } catch { deleteError = error.localizedDescription }
                trip.onUploadPreference?(uploadOptIn)
            }
        } message: { Text("Local trips and exports cannot be recovered.") }
        .alert("Could not finish deleting data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}
