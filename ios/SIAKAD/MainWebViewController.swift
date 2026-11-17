import UIKit
import WebKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// Pembungkus WKWebView untuk SIAKAD SMK PGRI 1 Ponorogo.
///
/// Fitur yang disamakan dengan versi Android:
/// - splash logo + indikator muat, halaman "Coba Lagi" saat offline
/// - bilah progres, navigasi maju/mundur, tarik-untuk-muat-ulang
/// - unggah berkas/foto, unduh berkas, penanganan tautan eksternal
/// - hanya domain sekolah yang dibuka di dalam aplikasi
final class MainWebViewController: UIViewController {

    private enum Config {
        static let startURL = URL(string: "https://siakad.smkpgri1po.sch.id/admin/login")!
        static let allowedHost = "siakad.smkpgri1po.sch.id"
        /// Splash minimal tampil selama ini agar tidak berkedip.
        static let splashMinimum: TimeInterval = 0.8
        /// Jaring pengaman bila halaman tidak pernah selesai dimuat.
        static let splashMaximum: TimeInterval = 6.0
    }

    private enum Palette {
        static let brand = UIColor(red: 0.059, green: 0.318, blue: 0.196, alpha: 1)       // #0F5132
        static let brandAccent = UIColor(red: 0.106, green: 0.478, blue: 0.271, alpha: 1)  // #1B7A45
        static let textPrimary = UIColor(red: 0.122, green: 0.161, blue: 0.200, alpha: 1)  // #1F2933
        static let textSecondary = UIColor(red: 0.380, green: 0.431, blue: 0.486, alpha: 1) // #616E7C
    }

    // MARK: - Tampilan

    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var splashView: UIView!
    private var errorView: UIView!
    private var errorLabel: UILabel!
    private var toolbar: UIToolbar!
    private var backItem: UIBarButtonItem!
    private var forwardItem: UIBarButtonItem!
    private var refreshItem: UIBarButtonItem!

    // MARK: - Status

    private var progressObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    /// Completion handler untuk <input type="file"> yang sedang menunggu.
    private var pendingFileHandler: (([URL]?) -> Void)?
    /// Lokasi berkas hasil unduhan terakhir (untuk share sheet).
    private var lastDownloadURL: URL?

    private let splashShownAt = Date()
    private var splashHidden = false
    private var splashWorkItem: DispatchWorkItem?
    private var mainFrameFailed = false

    // MARK: - Siklus hidup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        configureWebView()
        configureProgressView()
        configureToolbar()
        configureErrorView()
        configureSplash()

        webView.load(URLRequest(url: Config.startURL))
        scheduleSplashHide(after: Config.splashMaximum)
    }

    deinit {
        splashWorkItem?.cancel()
        progressObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - Penyiapan tampilan

    private func configureWebView() {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        // Ditambahkan ke User-Agent bawaan tanpa mengubah identitas perangkat.
        configuration.applicationNameForUserAgent = "SIAKADApp/1.3"

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.backgroundColor = .white
        webView.backgroundColor = .white
        webView.scrollView.keyboardDismissMode = .interactive
        view.addSubview(webView)

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = Palette.brand
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.updateProgress(webView.estimatedProgress)
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            self?.updateToolbarItems()
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            self?.updateToolbarItems()
        }
    }

    private func configureProgressView() {
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = Palette.brandAccent
        progressView.trackTintColor = .clear
        progressView.progress = 0
        progressView.isHidden = true
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    private func configureToolbar() {
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.tintColor = Palette.brand

        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        toolbar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            toolbar.scrollEdgeAppearance = appearance
        }

        backItem = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"),
                                   style: .plain, target: self, action: #selector(goBack))
        forwardItem = UIBarButtonItem(image: UIImage(systemName: "chevron.forward"),
                                      style: .plain, target: self, action: #selector(goForward))
        refreshItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"),
                                      style: .plain, target: self, action: #selector(handleRefresh))
        backItem.accessibilityLabel = "Kembali"
        forwardItem.accessibilityLabel = "Maju"
        refreshItem.accessibilityLabel = "Muat ulang"

        toolbar.items = [
            backItem,
            UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil),
            forwardItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            refreshItem,
        ]
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])
        updateToolbarItems()
    }

    private func configureErrorView() {
        errorView = UIView()
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.backgroundColor = .white
        errorView.isHidden = true
        view.addSubview(errorView)

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = Palette.textSecondary
        icon.setContentHuggingPriority(.required, for: .vertical)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Tidak dapat memuat halaman"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = Palette.textPrimary
        title.textAlignment = .center
        title.numberOfLines = 0

        errorLabel = UILabel()
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.text = "Periksa koneksi internet Anda, lalu coba lagi."
        errorLabel.font = .systemFont(ofSize: 15, weight: .regular)
        errorLabel.textColor = Palette.textSecondary
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0

        let retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Coba Lagi", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.backgroundColor = Palette.brand
        retryButton.layer.cornerRadius = 10
        retryButton.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, errorLabel, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: errorLabel)
        errorView.addSubview(stack)

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorView.trailingAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),

            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            retryButton.widthAnchor.constraint(equalToConstant: 170),
            retryButton.heightAnchor.constraint(equalToConstant: 46),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: errorView.widthAnchor, constant: -64),
        ])
    }

    private func configureSplash() {
        splashView = UIView()
        splashView.translatesAutoresizingMaskIntoConstraints = false
        splashView.backgroundColor = .white
        view.addSubview(splashView)

        let logo = UIImageView(image: UIImage(named: "LaunchLogo"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        if logo.image == nil {
            logo.image = UIImage(systemName: "graduationcap.fill")
            logo.tintColor = Palette.brand
        }

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "SIAKAD"
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = Palette.brand
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "SMK PGRI 1 Ponorogo"
        subtitle.font = .systemFont(ofSize: 15, weight: .medium)
        subtitle.textColor = Palette.textSecondary
        subtitle.textAlignment = .center

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Palette.brand
        spinner.startAnimating()

        let loading = UILabel()
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.text = "Menyiapkan halaman\u{2026}"
        loading.font = .systemFont(ofSize: 13, weight: .regular)
        loading.textColor = Palette.textSecondary
        loading.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [logo, title, subtitle, spinner, loading])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(18, after: subtitle)
        splashView.addSubview(stack)

        NSLayoutConstraint.activate([
            splashView.topAnchor.constraint(equalTo: view.topAnchor),
            splashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splashView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: splashView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: splashView.centerYAnchor, constant: -12),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: splashView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: splashView.trailingAnchor, constant: -24),

            logo.widthAnchor.constraint(equalToConstant: 116),
            logo.heightAnchor.constraint(equalToConstant: 116),
        ])
    }

    // MARK: - Aksi

    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func handleRefresh() {
        if webView.isLoading {
            webView.stopLoading()
            webView.scrollView.refreshControl?.endRefreshing()
            updateProgress(1)
            return
        }
        errorView.isHidden = true
        webView.isHidden = false
        mainFrameFailed = false
        webView.reload()
    }

    @objc private func handleRetry() {
        errorView.isHidden = true
        webView.isHidden = false
        mainFrameFailed = false
        updateProgress(0)
        webView.load(URLRequest(url: Config.startURL))
    }

    // MARK: - Status tampilan

    private func updateProgress(_ value: Double) {
        let progress = Float(max(0, min(1, value)))
        progressView.setProgress(progress, animated: progress > 0 && progress < 1)
        progressView.isHidden = progress >= 1 || progress <= 0
    }

    private func updateToolbarItems() {
        backItem?.isEnabled = webView?.canGoBack ?? false
        forwardItem?.isEnabled = webView?.canGoForward ?? false
    }

    private func showError(_ message: String?) {
        mainFrameFailed = true
        webView.scrollView.refreshControl?.endRefreshing()
        progressView.isHidden = true
        errorLabel.text = {
            if let message = message, !message.isEmpty {
                return message
            }
            return "Periksa koneksi internet Anda, lalu coba lagi."
        }()
        errorView.isHidden = false
        webView.isHidden = true
        scheduleSplashHide(after: 0)
    }

    // MARK: - Splash

    private func scheduleSplashHide(after interval: TimeInterval) {
        guard !splashHidden else { return }
        splashWorkItem?.cancel()
        let elapsed = Date().timeIntervalSince(splashShownAt)
        let delay = max(interval, max(Config.splashMinimum - elapsed, 0))
        let item = DispatchWorkItem { [weak self] in self?.fadeOutSplash() }
        splashWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func fadeOutSplash() {
        guard !splashHidden, let splash = splashView else { return }
        splashHidden = true
        splashWorkItem?.cancel()
        splashWorkItem = nil
        UIView.animate(withDuration: 0.28, animations: {
            splash.alpha = 0
        }, completion: { _ in
            splash.removeFromSuperview()
        })
    }

    // MARK: - Tautan

    private func isInternal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" { return true }
        guard scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == Config.allowedHost || host.hasSuffix("." + Config.allowedHost)
    }

    private func isExternalScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "tel", "mailto", "sms", "whatsapp",
                "geo", "maps", "market", "intent", "itms-apps", "itms"].contains(scheme)
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            if !success {
                self?.showAlert(title: "Tautan tidak dapat dibuka",
                                message: "Tidak ada aplikasi untuk membuka tautan ini.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Unggah berkas

    private func finishFileSelection(_ urls: [URL]?) {
        let handler = pendingFileHandler
        pendingFileHandler = nil
        handler?(urls)
    }

    private func presentFileSourceOptions(allowsMultiple: Bool) {
        let sheet = UIAlertController(title: "Pilih berkas", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Pilih dari Galeri", style: .default) { [weak self] _ in
            self?.presentPhotoPicker(allowsMultiple: allowsMultiple)
        })
        sheet.addAction(UIAlertAction(title: "Pilih dari Berkas", style: .default) { [weak self] _ in
            self?.presentDocumentPicker(allowsMultiple: allowsMultiple)
        })
        sheet.addAction(UIAlertAction(title: "Batal", style: .cancel) { [weak self] _ in
            self?.finishFileSelection(nil)
        })
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 88, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentDocumentPicker(allowsMultiple: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentPhotoPicker(allowsMultiple: Bool) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = allowsMultiple ? 0 : 1
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadsDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Unggahan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Unduhan

    private func downloadsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func uniqueDestination(filename: String) -> URL {
        let dir = downloadsDirectory()
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleaned.isEmpty ? "unduhan" : cleaned
        var candidate = dir.appendingPathComponent(baseName)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func shouldDownload(_ response: WKNavigationResponse) -> Bool {
        if !response.canShowMIMEType { return true }
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.contains("attachment") {
            return true
        }
        return false
    }

    private func presentShareSheet(for url: URL) {
        guard presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 88, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activity, animated: true)
    }

    private func presentDownloadOptions(for url: URL) {
        guard presentedViewController == nil else { return }
        let sheet = UIAlertController(
            title: "Unduhan selesai",
            message: url.lastPathComponent,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Bagikan / Simpan", style: .default) { [weak self] _ in
            self?.presentShareSheet(for: url)
        })
        sheet.addAction(UIAlertAction(title: "Tutup", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 88, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension MainWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if isInternal(url) {
            if #available(iOS 14.5, *), navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        } else if isExternalScheme(url) {
            openExternally(url)
            decisionHandler(.cancel)
        } else {
            // Skema lain (mis. file:, javascript:) diblokir demi keamanan.
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if shouldDownload(navigationResponse) {
            if #available(iOS 14.5, *) {
                decisionHandler(.download)
            } else {
                if let url = navigationResponse.response.url { openExternally(url) }
                decisionHandler(.cancel)
            }
            return
        }
        decisionHandler(.allow)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
        updateProgress(1)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
        updateProgress(1)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        mainFrameFailed = false
        updateProgress(max(webView.estimatedProgress, 0.05))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateProgress(1)
        webView.scrollView.refreshControl?.endRefreshing()
        if !mainFrameFailed {
            errorView.isHidden = true
            webView.isHidden = false
        }
        updateToolbarItems()
        scheduleSplashHide(after: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        // Muat ulang/stopLoading memicu NSURLErrorCancelled; bukan kegagalan nyata.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            return
        }
        updateProgress(0)
        webView.scrollView.refreshControl?.endRefreshing()
        let message = nsError.localizedDescription.isEmpty
            ? "Periksa koneksi internet Anda, lalu coba lagi."
            : nsError.localizedDescription
        showError(message)
    }
}

// MARK: - WKUIDelegate

extension MainWebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target="_blank" / window.open dibuka di tampilan yang sama.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            let scheme = url.scheme?.lowercased() ?? ""
            if isInternal(url) && (scheme == "http" || scheme == "https") {
                DispatchQueue.main.async {
                    webView.load(navigationAction.request)
                }
            } else if isExternalScheme(url) {
                openExternally(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        pendingFileHandler?(nil)
        pendingFileHandler = completionHandler
        presentFileSourceOptions(allowsMultiple: parameters.allowsMultipleSelection)
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Aplikasi ini hanya untuk login/unggah berkas, bukan kamera/mikrofon.
        decisionHandler(.deny)
    }
}

// MARK: - UIDocumentPickerDelegate

extension MainWebViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishFileSelection(urls.isEmpty ? nil : urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishFileSelection(nil)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension MainWebViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) { [weak self] in
            self?.handlePickedResults(results)
        }
    }

    private func handlePickedResults(_ results: [PHPickerResult]) {
        guard let handler = pendingFileHandler else { return }
        guard !results.isEmpty else {
            finishFileSelection(nil)
            return
        }

        let directory = uploadsDirectory()
        let lock = NSLock()
        var destinations = [URL?](repeating: nil, count: results.count)
        let group = DispatchGroup()

        for (index, result) in results.enumerated() {
            let provider = result.itemProvider
            guard let typeIdentifier = provider.registeredTypeIdentifiers.first else { continue }
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                defer { group.leave() }
                guard let url = url else { return }
                let ext = url.pathExtension.isEmpty
                    ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "jpg")
                    : url.pathExtension
                let destination = directory.appendingPathComponent("foto-\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    lock.lock()
                    destinations[index] = destination
                    lock.unlock()
                } catch {
                    // Lewati berkas yang gagal disalin.
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let urls = destinations.compactMap { $0 }
            self.pendingFileHandler = nil
            handler(urls.isEmpty ? nil : urls)
        }
    }
}

// MARK: - WKDownloadDelegate (iOS 14.5+)

@available(iOS 14.5, *)
extension MainWebViewController: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let destination = uniqueDestination(filename: suggestedFilename)
        lastDownloadURL = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = lastDownloadURL else { return }
        lastDownloadURL = nil
        presentDownloadOptions(for: url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        lastDownloadURL = nil
        showAlert(title: "Gagal mengunduh berkas", message: error.localizedDescription)
    }
}
