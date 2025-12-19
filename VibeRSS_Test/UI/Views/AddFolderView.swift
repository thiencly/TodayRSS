import SwiftUI

struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onAdd: (Folder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Section name", text: $name)
                }
            }
            .navigationTitle("Add Section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdd(Folder(name: trimmed))
                        dismiss()
                    } label: {
                        Text("Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
