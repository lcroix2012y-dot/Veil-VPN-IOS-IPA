import Foundation

/// Même logique que Proxies.kt : listes publiques -> test HTTPS réel -> géolocalisation -> 1 meilleur proxy par pays.
enum Proxies {
    // spys.me = liste texte du site spys.one (les pages HTML sont obfusquées)
    private static let sources = [
        "https://spys.me/proxy.txt",
        "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt",
        "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt"
    ]
    private static let maxCandidates = 1500
    private static let concurrency = 100
    private static let timeout: TimeInterval = 8

    struct Working: Sendable { let host: String; let port: Int; let ms: Int }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func httpGet(_ url: String) async throws -> String {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await URLSession.shared.data(for: req)
        return String(decoding: d, as: UTF8.self)
    }

    /// Durée en ms si le proxy laisse passer une vraie connexion HTTPS (certificat vérifié par iOS).
    static func test(host: String, port: Int, timeout: TimeInterval = Proxies.timeout) async -> Int? {
        let cfg = URLSessionConfiguration.ephemeral
        // Clés CFNetwork (valeurs littérales : les constantes ne sont pas exposées sur iOS)
        cfg.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port
        ]
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        let session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let t0 = Date()
        var req = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (_, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 204 else { return nil }
            return Int(Date().timeIntervalSince(t0) * 1000)
        } catch {
            return nil
        }
    }

    private static func probe(_ p: String) async -> Working? {
        let parts = p.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        let host = String(parts[0])
        guard let ms = await test(host: host, port: port) else { return nil }
        return Working(host: host, port: port, ms: ms)
    }

    private static func geolocate(_ ips: [String]) async -> [String: (String, String)] {
        var out: [String: (String, String)] = [:]
        var i = 0
        while i < ips.count {
            let chunk = Array(ips[i ..< min(i + 100, ips.count)])
            i += 100
            do {
                var req = URLRequest(url: URL(string: "http://ip-api.com/batch?fields=status,countryCode,city,query")!,
                                     timeoutInterval: 15)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: chunk)
                let (d, _) = try await URLSession.shared.data(for: req)
                if let arr = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                    for r in arr where (r["status"] as? String) == "success" {
                        if let q = r["query"] as? String, let cc = r["countryCode"] as? String {
                            out[q] = (cc, r["city"] as? String ?? "")
                        }
                    }
                }
            } catch {
                // on continue avec ce qu'on a
            }
        }
        return out
    }

    /// Cherche des proxys, ne garde que ceux qui font passer le HTTPS, et renvoie le plus rapide
    /// pour chaque pays de la liste maître (clé = id du pays).
    /// `extra` = proxys déjà connus, retestés en plus des nouveaux.
    static func refresh(countries: [Country], extra: [String],
                        progress: @escaping @Sendable (String) -> Void) async -> [String: Found] {
        progress("Récupération des listes…")
        let re = try! NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})"#)
        var cands: [String] = []
        var seen = Set<String>()
        for src in sources {
            guard let txt = try? await httpGet(src) else { continue }
            let ns = txt as NSString
            var got = 0
            for m in re.matches(in: txt, range: NSRange(location: 0, length: ns.length)) {
                let p = "\(ns.substring(with: m.range(at: 1))):\(ns.substring(with: m.range(at: 2)))"
                if seen.insert(p).inserted { cands.append(p) }
                got += 1
            }
            progress("\(got) adresses reçues")
        }
        var list: [String] = []
        var seen2 = Set<String>()
        for p in extra + Array(cands.shuffled().prefix(maxCandidates)) where seen2.insert(p).inserted {
            list.append(p)
        }
        if list.isEmpty { return [:] }

        var working: [Working] = []
        var done = 0
        let total = list.count
        await withTaskGroup(of: Working?.self) { group in
            var it = list.makeIterator()
            var active = 0
            while active < concurrency, let p = it.next() {
                group.addTask { await Proxies.probe(p) }
                active += 1
            }
            while let r = await group.next() {
                done += 1
                if let r = r { working.append(r) }
                if done % 25 == 0 || done == total { progress("Test HTTPS : \(done) / \(total)") }
                if let p = it.next() { group.addTask { await Proxies.probe(p) } }
            }
        }
        let ok = Array(working.sorted { $0.ms < $1.ms }.prefix(300))
        if ok.isEmpty { return [:] }

        progress("\(ok.count) proxy(s) HTTPS — recherche des pays…")
        let info = await geolocate(ok.map { $0.host })

        var byCode: [String: Found] = [:]
        for w in ok {
            guard let (cc, city) = info[w.host] else { continue }
            if byCode[cc] == nil { byCode[cc] = Found(host: w.host, port: w.port, city: city) }
        }
        var result: [String: Found] = [:]
        for c in countries {
            if let f = byCode[c.code] { result[c.id] = f }
        }
        return result
    }
}
