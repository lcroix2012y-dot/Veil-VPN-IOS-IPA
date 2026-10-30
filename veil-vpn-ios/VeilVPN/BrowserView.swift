import SwiftUI
import WebKit

/// Équivalent de BrowserActivity.kt : navigateur intégré dont le trafic passe par le proxy choisi.
/// (Le proxy est posé sur WKWebsiteDataStore.default(), que ce WKWebView utilise.)
@MainActor
final class BrowserModel: ObservableObject {
    let webView: WKWebView
    @Published var address = ""
    @Published var progress: Double = 0
    private var obsProgress: NSKeyValueObservation?
    private var obsURL: NSKeyValueObservation?

    init() {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0x0E / 255, green: 0x13 / 255, blue: 0x30 / 255, alpha: 1)
        self.webView = wv
        obsProgress = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
            Task { @MainActor in self?.progress = w.estimatedProgress }
        }
        obsURL = wv.observe(\.url, options: [.new]) { [weak self] w, _ in
            Task { @MainActor in if let u = w.url?.absoluteString { self?.address = u } }
        }
        wv.load(URLRequest(url: URL(string: "https://duckduckgo.com")!))
    }

    func go(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        let target: String
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            target = t
        } else if !t.contains(" ") && t.contains(".") {
            target = "https://" + t
        } else {
            target = "https://duckduckgo.com/?q=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)
        }
        if let url = URL(string: target) { webView.load(URLRequest(url: url)) }
    }
}

struct BrowserView: View {
    let connected: Bool
    let onClose: () -> Void
    @StateObject private var model = BrowserModel()
    @FocusState private var focused: Bool

    private let bg = Color(red: 0x0E / 255, green: 0x13 / 255, blue: 0x30 / 255)
    private let card = Color(red: 0x1B / 255, green: 0x22 / 255, blue: 0x50 / 255)
    private let muted = Color(red: 0x8E / 255, green: 0x97 / 255, blue: 0xC9 / 255)

    var body: some View {
        VStack(spacing: 0) {
            Text(connected ? "● Connecté — navigation via le proxy Veil"
                           : "● Non connecté — votre vraie adresse IP est utilisée")
                .font(.system(size: 12.5))
                .foregroundColor(connected ? Color(red: 0x22 / 255, green: 0xC9 / 255, blue: 0x8F / 255)
                                           : Color(red: 1, green: 0x6B / 255, blue: 0x7A / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)

            HStack(spacing: 4) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                TextField("", text: $model.address,
                          prompt: Text("Rechercher ou saisir une adresse").foregroundColor(muted))
                    .focused($focused)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .onSubmit { model.go(model.address); focused = false }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(card)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .opacity(model.progress > 0 && model.progress < 1 ? 1 : 0)
                .frame(height: 3)

            BrowserWebView(webView: model.webView)
        }
        .background(bg.ignoresSafeArea())
    }
}

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
