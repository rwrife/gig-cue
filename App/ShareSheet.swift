import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps UIActivityViewController for user-initiated, local export through
/// the native iOS share sheet. The destination is always user-selected and
/// nothing here performs a network call itself.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// User-picked JSON file import for restore previews. The picker only hands
/// back data; nothing is written until the user confirms the preview.
struct JSONDocumentPicker: UIViewControllerRepresentable {
    let onComplete: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Data?) -> Void
        init(onComplete: @escaping (Data?) -> Void) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onComplete(nil); return }
            // Security-scoped read of a user-selected file; read-only.
            guard url.startAccessingSecurityScopedResource() else { onComplete(nil); return }
            defer { url.stopAccessingSecurityScopedResource() }
            onComplete(try? Data(contentsOf: url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(nil)
        }
    }
}
