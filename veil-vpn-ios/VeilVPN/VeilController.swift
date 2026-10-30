import SwiftUI
import WebKit
import Network

/// Équivalent de MainActivity.kt : héberge l'UI (index.html) et expose le « pont » natif.
/// Côté JS, l'objet `Android` est recréé par un petit shim qui envoie des messages à Swift.
@MainActor
final class VeilController: NSObject, ObservableObject, WKScriptMessageHandler {
    let store: Store
    let webView: WKWebView
    @Published var showBrowser = false
    private var refreshing = false

    // MARK: - Init

    override init() {
        let store = Store()
        let ucc = WKUserContentController()
        let shim = """
        window.__veilState = \(VeilController.stateJSON(store));
        (function(){
          function post(o){ window.webkit.messageHandlers.veil.postMessage(o); }
          window.Android = {
            getState: function(){ return JSON.stringify(window.__veilState); },
            select: function(id){ post({cmd:'select', id:id}); },
            connect: function(){ post({cmd:'connect'}); },
            disconnect: function(){ post({cmd:'disconnect'}); },
            refresh: function(){ post({cmd:'refresh'}); },
            openBrowser: function(){ post({cmd:'openBrowser'}); }
          };
        })();
        """
        ucc.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0x0E / 255, green: 0x13 / 255, blue: 0x30 / 255, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        self.store = store
        self.webView = wv
        super.init()

        ucc.add(self, name: "veil")
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: - État

    private static func stateDict(_ store: Store) -> [String: Any] {
        let servers: [[String: Any]] = store.servers().map {
            ["id": $0.id, "country": $0.country, "code": $0.code, "city": $0.city, "available": $0.available]
        }
        return [
            "servers": servers,
            "selected": store.selected,
            "connectedId": AppState.connectedId.map { $0 as Any } ?? NSNull(),
            "since": AppState.since,
            "lastUpdate": store.lastUpdate
        ]
    }

    private static func stateJSON(_ store: Store) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: stateDict(store)),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    private func stateJSON() -> String { VeilController.stateJSON(store) }

    private func jsQuote(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]),
              let t = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(t.dropFirst().dropLast())
    }

    private func emit(_ ev: String, _ data: String = "") {
        webView.evaluateJavaScript("window.onNative(\(jsQuote(ev)),\(jsQuote(data)))", completionHandler: nil)
    }

    // MARK: - Proxy (WKWebsiteDataStore, iOS 17+)

    private func applyProxy(_ s: Server) {
        guard let p = UInt16(exactly: s.port), let port = NWEndpoint.Port(rawValue: p) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(s.host), port: port)
        WKWebsiteDataStore.default().proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint)]
    }

    private func clearProxy() {
        WKWebsiteDataStore.default().proxyConfigurations = []
    }

    // MARK: - Actions

    private func doConnect() {
        let sel = store.selected
        guard let s = store.servers().first(where: { $0.id == sel && $0.available }) else {
            emit("error", "Aucun serveur disponible. Appuyez sur « Actualiser les proxys ».")
            return
        }
        emit("connecting")
        Task {
            let ms = await Proxies.test(host: s.host, port: s.port)
            if ms == nil {
                emit("error", "Ce serveur ne répond pas. Choisissez-en un autre ou actualisez les proxys.")
            } else {
                applyProxy(s)
                AppState.connectedId = s.id
                AppState.since = Int64(Date().timeIntervalSince1970 * 1000)
                emit("connected", stateJSON())
            }
        }
    }

    private func doDisconnect() {
        clearProxy()
        AppState.connectedId = nil
        AppState.since = 0
        emit("disconnected", stateJSON())
    }

    private func doRefresh() {
        if refreshing { return }
        refreshing = true
        emit("refreshStart")
        let countries = store.countries
        let extra = store.servers().filter { $0.available }.map { "\($0.host):\($0.port)" }
        Task {
            let found = await Proxies.refresh(countries: countries, extra: extra) { [weak self] msg in
                Task { @MainActor in self?.emit("progress", msg) }
            }
            if found.isEmpty {
                emit("error", "Aucun proxy HTTPS n'a répondu. Liste conservée, réessayez plus tard.")
                emit("refreshDone", stateJSON())
            } else {
                store.applyRefresh(found)
                if let cid = AppState.connectedId {
                    if let s = store.servers().first(where: { $0.id == cid }), s.available {
                        applyProxy(s)
                    } else {
                        doDisconnect()
                    }
                }
                emit("refreshDone", stateJSON())
            }
            refreshing = false
        }
    }

    // MARK: - Pont JS -> Swift

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "select":      if let id = body["id"] as? String { store.selected = id }
        case "connect":     doConnect()
        case "disconnect":  doDisconnect()
        case "refresh":     doRefresh()
        case "openBrowser": showBrowser = true
        default: break
        }
    }
}

/// Enveloppe SwiftUI du WKWebView de l'UI principale.
struct VeilWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
