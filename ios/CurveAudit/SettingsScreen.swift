import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("curveaudit.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("curveaudit.uploadOptIn") private var uploadOptIn = false
    @AppStorage("curveaudit.onboardingComplete") private var onboarded = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section {
                Picker("Prompt style", selection: $promptStyle) {
                    ForEach(PromptStyle.allCases) { style in Text(style.rawValue).tag(style.rawValue) }
                }.pickerStyle(.inline).accessibilityIdentifier("promptStyle")
                Text("Spoken prompts use: “\(spokenWarning)” No numeric speed is spoken. Chime only uses a sound instead. Under-18 driver has no in-drive sound.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Hands-free prompts") }
            Section {
                Toggle("Anonymous pass uploads", isOn: $uploadOptIn).accessibilityIdentifier("settingsUpload")
                Text("Opt-in only. No account, device ID, or route trace. Public statistics require at least 20 passes across more than one hour bucket. Under-18 driver has no upload while moving.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !trip.isConnected {
                    Text("Upload service is not connected in this UI preview.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Privacy") }
            Section {
                LabeledContent("Driver choice", value: "Ask every trip")
                Text("Nothing is pre-selected. Set up the phone while parked. Camera stays off in Co-pilot mode.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Trip setup") }
            Section {
                Button("Delete all data", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteAllData")
                Text("Deletes local trips, pass history, timing memory, saved exports, and preferences, and stops uploads. The bundled road file stays installed. Previously uploaded anonymous rows cannot be linked back to this phone.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("On this iPhone") }
            Section {
                Text("Screening, not driving advice. The range is not an advisory speed.")
                Text("Road geometry and surface labels: Arkansas GIS Office.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        .confirmationDialog("Delete all local data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                uploadOptIn = false
                trip.onUploadPreference?(false)
                do {
                    try trip.deleteAllData()
                    try LocalTripExport.deleteAll()
                    promptStyle = PromptStyle.normal.rawValue
                    onboarded = false
                } catch { deleteError = error.localizedDescription }
            }
        } message: { Text("Local trips and exports cannot be recovered.") }
        .alert("Could not finish deleting data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}
