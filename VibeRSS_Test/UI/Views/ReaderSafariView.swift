import SwiftUI
import SafariServices

struct ReaderSafariView: UIViewControllerRepresentable {
    let url: URL
    var entersReaderIfAvailable: Bool = true  // Auto-enter reader mode when available

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        vc.preferredControlTintColor = .systemBlue
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
