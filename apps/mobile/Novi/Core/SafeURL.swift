import Foundation

enum NetworkURLPolicy {
    static func api(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.host != nil else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        #if DEBUG
        return url.scheme?.lowercased() == "http" && isLoopback(url.host)
        #else
        return false
        #endif
    }

    static func external(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host, !isPrivateHost(host)
        else { return nil }
        return url
    }

    private static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func isPrivateHost(_ raw: String) -> Bool {
        let host = raw.lowercased()
        if isLoopback(host) || host.hasSuffix(".local") || host == "0.0.0.0" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:")
        }
        return octets[0] == 10 || octets[0] == 127 ||
            (octets[0] == 169 && octets[1] == 254) ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
    }
}
