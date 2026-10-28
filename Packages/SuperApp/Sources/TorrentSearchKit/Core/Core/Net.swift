import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CloudflareChallengeError: LocalizedError {
    let url: String
    var errorDescription: String? { L("Bloqueado pelo Cloudflare. Desbloqueie o buscador na tela de buscadores.") }
}

struct HTTPStatusError: LocalizedError {
    let status: Int
    var errorDescription: String? { L("O site respondeu com erro HTTP %ld.", status) }
}

/// Cliente HTTP do app. Só fala com os sites dos buscadores que o usuário ativou.
/// Não há analytics, telemetria nem envio de dados para terceiros.
final class Net: NSObject, URLSessionTaskDelegate {
    static let shared = Net()

    /// User-agent usado no app e no WebView do Cloudflare (precisam ser iguais).
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    private static let maxRetries = 3

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.httpAdditionalHeaders = ["User-Agent": Net.userAgent]
        c.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: c)
    }()

    /// Sessão que não segue redirecionamentos (para ler o cabeçalho Location com o magnet).
    private lazy var noRedirectSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.httpCookieStorage = .shared
        c.httpAdditionalHeaders = ["User-Agent": Net.userAgent]
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    struct Response {
        let data: Data
        let http: HTTPURLResponse
        var status: Int { http.statusCode }
        var text: String { Net.decode(data, http) }
        func header(_ name: String) -> String? { http.value(forHTTPHeaderField: name) }
        var isSuccess: Bool { (200..<300).contains(status) }
    }

    static func decode(_ data: Data, _ http: HTTPURLResponse?) -> String {
        #if canImport(Darwin)
        if let name = http?.textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: enc) { return s }
            }
        }
        #endif
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1251) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    private func isChallenged(_ r: HTTPURLResponse) -> Bool {
        if let v = r.value(forHTTPHeaderField: "cf-mitigated"), v.lowercased() == "challenge" { return true }
        return r.statusCode == 403 || r.statusCode == 503
    }

    private func makeRequest(_ url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) throws -> URLRequest {
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.httpBody = body
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        // Cabeçalho Cookie manual + cookies salvos (ex.: cf_clearance) juntos.
        if let custom = headers.first(where: { $0.key.lowercased() == "cookie" })?.value {
            let stored = (HTTPCookieStorage.shared.cookies(for: u) ?? []).map { "\($0.name)=\($0.value)" }
            req.httpShouldHandleCookies = false
            req.setValue(([custom] + stored).joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        return req
    }

    /// Executa com até 3 tentativas e espera exponencial (como o Ktor do original).
    private func perform(_ req: URLRequest, session: URLSession) async throws -> Response {
        var attempt = 0
        while true {
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                let cf = http.value(forHTTPHeaderField: "cf-mitigated") != nil
                if (500..<600).contains(http.statusCode), !cf, attempt < Net.maxRetries {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 300_000_000))
                    continue
                }
                return Response(data: data, http: http)
            } catch let e as URLError where e.code != .cancelled && attempt < Net.maxRetries
                        && [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(e.code) {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 300_000_000))
            }
        }
    }

    // MARK: API usada pelos buscadores

    func get(_ url: String, headers: [String: String] = [:], followRedirects: Bool = true) async throws -> Response {
        let r = try await perform(try makeRequest(url, headers: headers), session: followRedirects ? session : noRedirectSession)
        if isChallenged(r.http) { throw CloudflareChallengeError(url: url) }
        return r
    }

    func getText(_ url: String, headers: [String: String] = [:]) async throws -> String {
        try await get(url, headers: headers).text
    }

    func getJson(_ url: String, headers: [String: String] = [:]) async throws -> Any? {
        let r = try await get(url, headers: headers)
        if r.data.isEmpty { return nil }
        return try? JSONSerialization.jsonObject(with: r.data, options: [.fragmentsAllowed])
    }

    /// Lê o cabeçalho `Location` sem seguir o redirecionamento.
    func getLocation(_ url: String, headers: [String: String] = [:]) async throws -> String? {
        try await get(url, headers: headers, followRedirects: false).header("Location")
    }

    func postJson(_ url: String, headers: [String: String] = [:]) async throws -> Any? {
        let r = try await perform(try makeRequest(url, method: "POST", headers: headers), session: session)
        if isChallenged(r.http) { throw CloudflareChallengeError(url: url) }
        if r.data.isEmpty { return nil }
        return try? JSONSerialization.jsonObject(with: r.data, options: [.fragmentsAllowed])
    }

    func postJson(_ url: String, payload: Any) async throws -> Any? {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let r = try await perform(try makeRequest(url, method: "POST", headers: ["Content-Type": "application/json"], body: body), session: session)
        if r.data.isEmpty { return nil }
        return try? JSONSerialization.jsonObject(with: r.data, options: [.fragmentsAllowed])
    }

    func submitForm(_ url: String, form: [(String, String)], headers: [String: String] = [:]) async throws -> String {
        let body = form.map { "\($0.0.formEncoded)=\($0.1.formEncoded)" }.joined(separator: "&")
        var h = headers
        h["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        let r = try await perform(try makeRequest(url, method: "POST", headers: h, body: Data(body.utf8)), session: session)
        return r.text
    }

    func getData(_ url: String) async throws -> Response {
        try await get(url)
    }

    /// Verifica rapidamente se a página está protegida pelo Cloudflare.
    func isUrlChallenged(_ url: String) async throws -> Bool {
        var req = try makeRequest(url)
        req.timeoutInterval = 8
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return true }
        return isChallenged(http)
    }

    // MARK: Cookies (Cloudflare)

    static func removeCookies(for url: String) {
        guard let host = URL(string: url)?.host else { return }
        let storage = HTTPCookieStorage.shared
        for c in storage.cookies ?? [] where host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            storage.deleteCookie(c)
        }
    }

    static func removeAllCookies() {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }
}

extension String {
    var formEncoded: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return (addingPercentEncoding(withAllowedCharacters: allowed) ?? self).replacingOccurrences(of: "%20", with: "+")
    }
}
