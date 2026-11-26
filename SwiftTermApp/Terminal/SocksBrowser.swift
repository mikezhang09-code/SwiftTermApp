//
//  SocksBrowser.swift
//  SwiftTermApp
//
//  A minimal in-app web browser whose traffic is routed through a running
//  dynamic (SOCKS5) port forward.  iOS has no system-wide SOCKS setting, but
//  since iOS 17 a WKWebView can be given a ProxyConfiguration(socksv5Proxy:),
//  so this browser loads pages "as if" from the SSH server the forward tunnels
//  through — the practical way to use ssh -D on an iPad.
//

import SwiftUI
import WebKit
import Network

@available(iOS 17.0, *)
final class SocksBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    let useSocksProxy: Bool

    @Published var urlText = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var pageTitle = ""
    @Published var loadError: String? = nil

    private var observers: [NSKeyValueObservation] = []

    init (localPort: Int, useSocksProxy: Bool = true) {
        self.useSocksProxy = useSocksProxy
        // A private data store so proxied browsing does not mix with anything else,
        // and cookies/cache vanish when the browser closes.
        let dataStore = WKWebsiteDataStore.nonPersistent ()
        if useSocksProxy {
            let endpoint = NWEndpoint.hostPort (host: "127.0.0.1",
                                                port: NWEndpoint.Port (integerLiteral: UInt16 (localPort & 0xffff)))
            let proxy = ProxyConfiguration (socksv5Proxy: endpoint)
            dataStore.proxyConfigurations = [proxy]
        }
        let config = WKWebViewConfiguration ()
        config.websiteDataStore = dataStore
        webView = WKWebView (frame: .zero, configuration: config)
        super.init ()
        webView.navigationDelegate = self

        observers.append (webView.observe (\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
            Task { @MainActor in self?.canGoBack = wv.canGoBack }
        })
        observers.append (webView.observe (\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
            Task { @MainActor in self?.canGoForward = wv.canGoForward }
        })
        observers.append (webView.observe (\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
            Task { @MainActor in self?.isLoading = wv.isLoading }
        })
        observers.append (webView.observe (\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in self?.progress = wv.estimatedProgress }
        })
        observers.append (webView.observe (\.title, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in self?.pageTitle = wv.title ?? "" }
        })
        observers.append (webView.observe (\.url, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in
                if let u = wv.url?.absoluteString { self?.urlText = u }
            }
        })
    }

    /// Loads what the user typed, tolerating bare hostnames and search terms.
    func go () {
        let trimmed = urlText.trimmingCharacters (in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var target = trimmed
        if !target.contains ("://") {
            let lower = target.lowercased ()
            if lower.hasPrefix ("localhost") || lower.hasPrefix ("127.0.0.1") || lower.hasPrefix ("[::1]") {
                target = "http://\(target)"
            } else if target.contains (" ") || !target.contains (".") {
                // A single token with no dot is treated as a search, otherwise a URL
                let q = target.addingPercentEncoding (withAllowedCharacters: .urlQueryAllowed) ?? target
                target = "https://www.google.com/search?q=\(q)"
            } else {
                target = "https://\(target)"
            }
        }
        guard let url = URL (string: target) else {
            loadError = "Invalid URL: \(target)"
            return
        }
        loadError = nil
        urlText = url.absoluteString
        webView.load (URLRequest (url: url))
    }

    func goBack () { webView.goBack () }
    func goForward () { webView.goForward () }
    func reloadOrStop () { if isLoading { webView.stopLoading () } else { loadError = nil; webView.reload () } }

    // MARK: WKNavigationDelegate

    func webView (_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView (_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        loadError = error.localizedDescription
    }

    func webView (_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        loadError = error.localizedDescription
    }
}

@available(iOS 17.0, *)
private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView (context: Context) -> WKWebView { webView }
    func updateUIView (_ uiView: WKWebView, context: Context) { }
}

@available(iOS 17.0, *)
struct SocksBrowserView: View {
    let localPort: Int
    let startURL: String
    let useSocksProxy: Bool

    @Environment(\.dismiss) var dismiss
    @StateObject private var model: SocksBrowserModel
    @FocusState private var urlFocused: Bool

    init (localPort: Int, startURL: String = "https://www.google.com", useSocksProxy: Bool = true) {
        self.localPort = localPort
        self.startURL = startURL
        self.useSocksProxy = useSocksProxy
        _model = StateObject (wrappedValue: SocksBrowserModel (localPort: localPort, useSocksProxy: useSocksProxy))
    }

    var body: some View {
        NavigationView {
            VStack (spacing: 0) {
                HStack (spacing: 8) {
                    TextField ("Search or enter address", text: $model.urlText)
                        .textFieldStyle (.roundedBorder)
                        .keyboardType (.URL)
                        .autocapitalization (.none)
                        .disableAutocorrection (true)
                        .focused ($urlFocused)
                        .submitLabel (.go)
                        .onSubmit { model.go (); urlFocused = false }
                    Button (action: { model.go (); urlFocused = false }) {
                        Image (systemName: "arrow.right.circle.fill")
                    }
                    .accessibilityLabel ("Go")
                    Button (action: { model.reloadOrStop () }) {
                        Image (systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    }
                }
                .padding (.horizontal)
                .padding (.vertical, 6)

                if model.isLoading {
                    ProgressView (value: model.progress)
                        .progressViewStyle (.linear)
                }

                if let loadError = model.loadError {
                    HStack (spacing: 8) {
                        Image (systemName: "exclamationmark.triangle.fill")
                            .foregroundColor (.orange)
                        Text (loadError)
                            .font (.caption)
                            .foregroundColor (.primary)
                            .lineLimit (3)
                        Spacer ()
                    }
                    .padding (.horizontal)
                    .padding (.vertical, 6)
                    .background (Color.orange.opacity (0.12))
                }

                WebViewContainer (webView: model.webView)
            }
            .navigationTitle (model.pageTitle.isEmpty ? (useSocksProxy ? "Proxied Browser" : "Local Forward Browser") : model.pageTitle)
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Done") { dismiss () }
                }
                ToolbarItemGroup (placement: .bottomBar) {
                    Button (action: { model.goBack () }) {
                        Image (systemName: "chevron.left")
                    }.disabled (!model.canGoBack)
                    Spacer ()
                    Button (action: { model.goForward () }) {
                        Image (systemName: "chevron.right")
                    }.disabled (!model.canGoForward)
                    Spacer ()
                    Label (useSocksProxy
                           ? "via SOCKS 127.0.0.1:\(String (localPort))"
                           : "via Local 127.0.0.1:\(String (localPort))",
                           systemImage: "lock.shield")
                        .font (.caption2)
                        .foregroundColor (.secondary)
                }
            }
            .onAppear {
                if model.urlText.isEmpty {
                    model.urlText = startURL
                    model.go ()
                }
            }
        }
        .navigationViewStyle (.stack)
    }
}
