import Foundation

struct Country { let id: String; let name: String; let code: String }

struct Server {
    let id: String, country: String, code: String
    let city: String, host: String, port: Int, available: Bool
}

struct Found { let host: String; let port: Int; let city: String }

/// État de connexion partagé (équivalent de AppState côté Android).
enum AppState {
    static var connectedId: String? = nil
    static var since: Int64 = 0
}

final class Store {
    private let defaults = UserDefaults.standard
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("servers.json")
    }

    private func readBundle(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let d = try? Data(contentsOf: url) else { return Data() }
        return d
    }

    /// Liste maître des pays : jamais modifiée par l'actualisation.
    lazy var countries: [Country] = {
        guard let arr = try? JSONSerialization.jsonObject(with: readBundle("countries")) as? [[String: Any]] else { return [] }
        return arr.compactMap { o in
            guard let id = o["id"] as? String, let name = o["country"] as? String, let code = o["code"] as? String else { return nil }
            return Country(id: id, name: name, code: code)
        }
    }()

    private func data() -> [String: Any] {
        let raw = (try? Data(contentsOf: fileURL)) ?? readBundle("servers_default")
        return (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
    }

    func servers() -> [Server] {
        let d = data()
        return countries.map { c in
            let o = d[c.id] as? [String: Any]
            let host = o?["host"] as? String ?? ""
            return Server(
                id: c.id, country: c.name, code: c.code,
                city: o?["city"] as? String ?? "",
                host: host,
                port: o?["port"] as? Int ?? 0,
                available: (o?["available"] as? Bool ?? false) && !host.isEmpty
            )
        }
    }

    /// Un pays trouvé => disponible. Pas trouvé => masqué (available=false) mais conservé.
    func applyRefresh(_ found: [String: Found]) {
        var d = data()
        for c in countries {
            let old = d[c.id] as? [String: Any]
            var o: [String: Any] = [:]
            if let f = found[c.id] {
                o["host"] = f.host
                o["port"] = f.port
                o["city"] = f.city.isEmpty ? c.name : f.city
                o["available"] = true
            } else {
                o["host"] = old?["host"] as? String ?? ""
                o["port"] = old?["port"] as? Int ?? 0
                o["city"] = old?["city"] as? String ?? ""
                o["available"] = false
            }
            d[c.id] = o
        }
        if let out = try? JSONSerialization.data(withJSONObject: d) {
            try? out.write(to: fileURL, options: .atomic)
        }
        defaults.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "last")
    }

    var lastUpdate: Int64 { Int64(defaults.object(forKey: "last") as? Int ?? 0) }

    var selected: String {
        get {
            let s = defaults.string(forKey: "selected") ?? ""
            let av = servers().filter { $0.available }
            return av.contains(where: { $0.id == s }) ? s : (av.first?.id ?? "")
        }
        set { defaults.set(newValue, forKey: "selected") }
    }
}
