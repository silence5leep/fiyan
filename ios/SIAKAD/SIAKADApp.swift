import SwiftUI

@main
struct SIAKADApp: App {
    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}

/// Menjembatani UIViewController (WKWebView) ke SwiftUI.
struct WebScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MainWebViewController {
        MainWebViewController()
    }

    func updateUIViewController(_ uiViewController: MainWebViewController, context: Context) {}
}
