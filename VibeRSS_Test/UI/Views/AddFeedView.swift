import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FeedStore
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onAdd: (Source) -> Void
    private let faviconService = FaviconService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title (optional)", text: $title)
                    TextField("Source URL (https://…)", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: add) {
                        if isSaving { ProgressView() } else { Text("Add") }
                    }.disabled(!isValidURL || isSaving)
                }
            }
        }
    }

    var isValidURL: Bool { URL(string: urlString)?.scheme?.hasPrefix("http") == true }

    func add() {
        if let url = URL(string: urlString) {
            isSaving = true; errorMessage = nil
            Task {
                let icon = await faviconService.resolveIcon(for: url)
                let feed = Feed(title: title.isEmpty ? (url.host ?? "Feed") : title, url: url, iconURL: icon)
                onAdd(feed)
                isSaving = false
                dismiss()
            }
        } else {
            isSaving = false
            errorMessage = "Invalid URL"
        }
    }
}
