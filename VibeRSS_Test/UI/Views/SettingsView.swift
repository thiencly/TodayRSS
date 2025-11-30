import SwiftUI

struct SettingsView: View {
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Collapse Hero Card on Launch", isOn: $heroCollapsedOnLaunch)
                } header: {
                    Text("Hero Card")
                } footer: {
                    Text("When enabled, the Today Highlights hero card will start collapsed when you open the app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
