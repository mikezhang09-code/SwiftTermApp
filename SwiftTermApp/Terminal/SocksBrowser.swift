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
final class SocksBrowserModel: ObservableObject {
    let webView: WKWebView

    @Published var urlText = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var pageTitle = ""

    private var observers: [NSKeyValueObservation] = []

    init (localPort: Int) {
        let endpoint = NWEndpoint.hostPort (host: "127.0.0.1",
                                            port: NWEndpoint.Port (integerLiteral: UInt16 (localPort & 0xffff)))
        let proxy = ProxyConfiguration (socksv5Proxy: endpoint)
        // A private data store so proxied browsing does not mix with anything else,
        // and cookies/cache vanish when the browser closes.
        let dataStore = WKWebsiteDataStore.nonPersistent ()
        dataStore.proxyConfigurations = [proxy]
        let config = WKWebViewConfiguration ()
        config.websiteDataStore = dataStore
        webView = WKWebView (frame: .zero, configuration: config)

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
        let trimmed = urlText.trimmingCharacters (in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var target = trimmed
        if !target.contains ("://") {
            // A single token with no dot is treated as a search, otherwise a URL
            if target.contains (" ") || !target.contains (".") {
                let q = target.addingPercentEncoding (withAllowedCharacters: .urlQueryAllowed) ?? target
                target = "https://www.google.com/search?q=\(q)"
            } else {
                target = "https://\(target)"
            }
        }
        guard let url = URL (string: target) else { return }
        webView.load (URLRequest (url: url))
    }

    func goBack () { webView.goBack () }
    func goForward () { webView.goForward () }
    func reloadOrStop () { if isLoading { webView.stopLoading () } else { webView.reload () } }
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

    @Environment(\.dismiss) var dismiss
    @StateObject private var model: SocksBrowserModel
    @FocusState private var urlFocused: Bool

    init (localPort: Int, startURL: String = "https://www.google.com") {
        self.localPort = localPort
        self.startURL = startURL
        _model = StateObject (wrappedValue: SocksBrowserModel (localPort: localPort))
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

                WebViewContainer (webView: model.webView)
            }
            .navigationTitle (model.pageTitle.isEmpty ? "Proxied Browser" : model.pageTitle)
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
                    Label ("via SOCKS 127.0.0.1:\(String (localPort))", systemImage: "lock.shield")
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
