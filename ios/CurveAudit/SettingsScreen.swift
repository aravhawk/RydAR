import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = false
    @AppStorage("rydar.dashEnabled") private var dashEnabled = false
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section {
                Picker("Prompt style", selection: $promptStyle) {
                    ForEach(PromptStyle.allCases) { style in Text(style.rawValue).tag(style.rawValue) }
                }.pickerStyle(.inline).accessibilityIdentifier("promptStyle")
                Text("“\(spokenWarning)”")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Hands-free prompts") }
            Section {
                Toggle("Anonymous pass uploads", isOn: $uploadOptIn).accessibilityIdentifier("settingsUpload")
                Text("Off unless you turn it on. No account and no route.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Privacy") }
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
                }.accessibilityIdentifier("treadSetting")
                Toggle("Dash mode", isOn: $dashEnabled).accessibilityIdentifier("dashMode")
                Text("Camera stays off unless Dash is on.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Trip setup") }
            Section {
                Button("Delete all data", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteAllData")
                Text("Clears trips on this iPhone. The road file stays.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("On this iPhone") }
            Section {
                Text("Screening range, not an advisory speed. Roads: Arkansas GIS Office.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        .confirmationDialog("Delete all local data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                uploadOptIn = false
                dashEnabled = false
                trip.onUploadPreference?(false)
                do {
                    try trip.deleteAllData()
                    try LocalTripExport.deleteAll()
                    promptStyle = PromptStyle.normal.rawValue
                    onboarded = false
                    TreadStore.clear()
                    treadRaw = ""
                } catch { deleteError = error.localizedDescription }
            }
        } message: { Text("Local trips and exports cannot be recovered.") }
        .alert("Could not finish deleting data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}
