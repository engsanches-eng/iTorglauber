import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uma legenda encontrada.
struct SubtitleResult: Identifiable, Hashable {
    let fileId: Int
    var id: Int { fileId }
    let language: SubtitleLanguage
    let release: String
    let fileName: String?
    let downloads: Int
    let hearingImpaired: Bool
    let fps: Double?
    let machineTranslated: Bool
    let aiTranslated: Bool
    let fromTrusted: Bool
    /// true = encontrada pelo hash do arquivo (sincronizada com este vídeo).
    var hashMatch: Bool
    let featureTitle: String?
    let year: Int?
    let season: Int?
    let episode: Int?
    let uploadDate: String?

    var displayTitle: String {
        if !release.isEmpty { return release }
        if let f = fileName, !f.isEmpty { return f }
        return featureTitle ?? "—"
    }
}

/// O que o nome do arquivo diz sobre o vídeo (para a busca por nome).
struct ParsedVideoName: Equatable {
    var query: String
    var year: Int?
    var season: Int?
    var episode: Int?

    /// "The.Show.S01E02.1080p.WEB.mkv" → query "The Show", temporada 1, episódio 2.
    /// "Movie.Name.2019.1080p.BluRay.mkv" → query "Movie Name", ano 2019.
    static func parse(_ fileName: String) -> ParsedVideoName {
        var base = (fileName as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: "[._]+", with: " ", options: .regularExpression)
        base = base.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        let ns = base as NSString
        let full = NSRange(location: 0, length: ns.length)

        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "[\\s\\-()]+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmed
        }

        // Série: S01E02 ou 1x02
        if let re = try? NSRegularExpression(pattern: "^(.*?)[\\s\\-]*\\b(?:s(\\d{1,2})\\s?e(\\d{1,3})|(\\d{1,2})x(\\d{2,3}))\\b", options: .caseInsensitive),
           let m = re.firstMatch(in: base, range: full) {
            let title = clean(ns.substring(with: m.range(at: 1)))
            let s = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) : Int(ns.substring(with: m.range(at: 4)))
            let e = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : Int(ns.substring(with: m.range(at: 5)))
            if !title.isEmpty { return ParsedVideoName(query: title, year: nil, season: s, episode: e) }
        }
        // Filme: título + ano
        if let re = try? NSRegularExpression(pattern: "^(.+?)[\\s(\\-]+((?:19|20)\\d{2})(?:\\)|\\s|$)", options: []),
           let m = re.firstMatch(in: base, range: full) {
            let title = clean(ns.substring(with: m.range(at: 1)))
            if !title.isEmpty { return ParsedVideoName(query: title, year: Int(ns.substring(with: m.range(at: 2))), season: nil, episode: nil) }
        }
        // Sem ano: corta no primeiro termo técnico (1080p, WEB-DL, x264…)
        let tech = "\\b(2160p|1080p|720p|480p|4k|uhd|hdr|web[\\s-]?dl|webrip|web|bluray|blu[\\s-]?ray|brrip|bdrip|dvdrip|hdtv|x264|x265|h264|h265|hevc|aac|ac3|dts|remux|proper|repack|dublado|legendado|dual)\\b"
        if let r = base.range(of: tech, options: [.regularExpression, .caseInsensitive]) {
            let title = clean(String(base[..<r.lowerBound]))
            if !title.isEmpty { return ParsedVideoName(query: title, year: nil, season: nil, episode: nil) }
        }
        return ParsedVideoName(query: clean(base), year: nil, season: nil, episode: nil)
    }
}

enum OpenSubtitlesError: LocalizedError {
    case missingApiKey
    case invalidApiKey
    case loginFailed(String)
    case quotaExceeded(String)
    case server(Int, String)
    case network(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return L("Configure a chave da API do OpenSubtitles em Ajustes.")
        case .invalidApiKey: return L("A chave da API do OpenSubtitles foi recusada. Confira em Ajustes.")
        case .loginFailed(let m): return m.isEmpty ? L("Usuário ou senha incorretos.") : m
        case .quotaExceeded(let m): return m.isEmpty ? L("Você atingiu o limite de downloads de hoje no OpenSubtitles.") : m
        case .server(let code, let m): return m.isEmpty ? L("O OpenSubtitles respondeu com erro %ld.", code) : m
        case .network(let m): return L("Sem conexão com o OpenSubtitles: %@", m)
        case .badResponse: return L("Resposta inesperada do OpenSubtitles.")
        }
    }
}

/// Cliente da API REST oficial do OpenSubtitles.com (HTTPS).
/// Só envia: hash do vídeo, nome limpo do arquivo, idiomas e a chave/conta do usuário.
struct OpenSubtitlesClient {
    static let userAgent = "SuperApp v1.0"

    let apiKey: String
    var token: String?
    var host: String = "api.opensubtitles.com"

    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }

    // MARK: Busca

    struct SearchOptions {
        var languages: [SubtitleLanguage]
        var includeHearingImpaired = true
        var includeMachineTranslated = false
    }

    /// Busca pelo hash e pelo nome ao mesmo tempo e junta os resultados.
    func search(hash: String?, name: ParsedVideoName, options: SearchOptions) async throws -> [SubtitleResult] {
        var common: [String: String] = [
            "languages": options.languages.map(\.code).sorted().joined(separator: ","),
            "machine_translated": options.includeMachineTranslated ? "include" : "exclude",
            "ai_translated": options.includeMachineTranslated ? "include" : "exclude",
        ]
        if !options.includeHearingImpaired { common["hearing_impaired"] = "exclude" }

        var byHash: [SubtitleResult] = []
        var hashError: Error?
        if let hash {
            var p = common
            p["moviehash"] = hash
            do { byHash = try await searchPage(p).map { var r = $0; r.hashMatch = true; return r } } catch { hashError = error }
        }

        var byName: [SubtitleResult] = []
        var nameError: Error?
        if !name.query.isEmpty {
            var p = common
            p["query"] = name.query.lowercased()
            if let s = name.season { p["season_number"] = String(s) }
            if let e = name.episode { p["episode_number"] = String(e) }
            if let y = name.year, name.season == nil { p["year"] = String(y) }
            do { byName = try await searchPage(p) } catch { nameError = error }
        }

        // Erros de chave/conta não podem ser escondidos.
        for e in [hashError, nameError].compactMap({ $0 }) {
            if case OpenSubtitlesError.invalidApiKey = e { throw e }
            if case OpenSubtitlesError.missingApiKey = e { throw e }
        }
        if byHash.isEmpty && byName.isEmpty, let e = hashError ?? nameError { throw e }

        var seen = Set<Int>()
        var merged: [SubtitleResult] = []
        for r in byHash + byName where !seen.contains(r.fileId) {
            seen.insert(r.fileId)
            merged.append(r)
        }
        return merged
    }

    private func searchPage(_ params: [String: String]) async throws -> [SubtitleResult] {
        // O OpenSubtitles pede parâmetros em ordem alfabética e em minúsculas (evita redirecionamento).
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/api/v1/subtitles"
        comps.queryItems = params.keys.sorted().map { URLQueryItem(name: $0, value: params[$0]) }
        guard let url = comps.url else { throw OpenSubtitlesError.badResponse }
        let data = try await send(request(url, method: "GET"))
        guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else { throw OpenSubtitlesError.badResponse }
        return decoded.data.flatMap { $0.results }
    }

    // MARK: Login e download

    struct LoginResult { let token: String; let host: String; let allowedDownloads: Int? }

    func login(username: String, password: String) async throws -> LoginResult {
        guard let url = URL(string: "https://api.opensubtitles.com/api/v1/login") else { throw OpenSubtitlesError.badResponse }
        var req = request(url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let data: Data
        do { data = try await send(req, isLogin: true) }
        catch OpenSubtitlesError.server(let code, let m) where code == 401 || code == 400 { throw OpenSubtitlesError.loginFailed(m) }
        guard let r = try? JSONDecoder().decode(LoginResponse.self, from: data), let token = r.token, !token.isEmpty else {
            throw OpenSubtitlesError.badResponse
        }
        let host = (r.base_url ?? "").replacingOccurrences(of: "https://", with: "").split(separator: "/").first.map(String.init)
        return LoginResult(token: token, host: (host?.isEmpty ?? true) ? "api.opensubtitles.com" : host!, allowedDownloads: r.user?.allowed_downloads)
    }

    struct DownloadResult { let data: Data; let remaining: Int?; let fileName: String? }

    func download(fileId: Int) async throws -> DownloadResult {
        guard let url = URL(string: "https://\(host)/api/v1/download") else { throw OpenSubtitlesError.badResponse }
        var req = request(url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileId, "sub_format": "srt"])
        let data = try await send(req)
        guard let r = try? JSONDecoder().decode(DownloadResponse.self, from: data),
              let link = r.link, let fileURL = URL(string: link), fileURL.scheme == "https" else {
            throw OpenSubtitlesError.badResponse
        }
        // O link é temporário e não precisa de chave nem token.
        let file: Data
        do {
            let (d, resp) = try await session.data(from: fileURL)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), !d.isEmpty else {
                throw OpenSubtitlesError.badResponse
            }
            file = d
        } catch let e as OpenSubtitlesError { throw e }
        catch { throw OpenSubtitlesError.network(error.localizedDescription) }
        return DownloadResult(data: file, remaining: r.remaining, fileName: r.file_name)
    }

    // MARK: HTTP

    private func request(_ url: URL, method: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token, !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func send(_ req: URLRequest, isLogin: Bool = false) async throws -> Data {
        guard !apiKey.trimmed.isEmpty else { throw OpenSubtitlesError.missingApiKey }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw OpenSubtitlesError.network(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw OpenSubtitlesError.badResponse }
        if (200..<300).contains(http.statusCode) { return data }
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.text ?? ""
        switch http.statusCode {
        case 403 where !isLogin: throw OpenSubtitlesError.invalidApiKey
        case 406, 429 where message.localizedCaseInsensitiveContains("download"): throw OpenSubtitlesError.quotaExceeded(message)
        default: throw OpenSubtitlesError.server(http.statusCode, message)
        }
    }
}

// MARK: - Formato JSON da API (tudo opcional para tolerar mudanças)

private struct SearchResponse: Decodable {
    let data: [Item]

    struct Item: Decodable {
        let attributes: Attributes?

        var results: [SubtitleResult] {
            guard let a = attributes else { return [] }
            let lang = SubtitleLanguage(a.language ?? "")
            return (a.files ?? []).compactMap { f in
                guard let id = f.file_id else { return nil }
                return SubtitleResult(
                    fileId: id, language: lang, release: a.release ?? "", fileName: f.file_name,
                    downloads: a.download_count ?? 0, hearingImpaired: a.hearing_impaired ?? false,
                    fps: (a.fps ?? 0) > 0 ? a.fps : nil, machineTranslated: a.machine_translated ?? false,
                    aiTranslated: a.ai_translated ?? false, fromTrusted: a.from_trusted ?? false,
                    hashMatch: a.moviehash_match ?? false,
                    featureTitle: a.feature_details?.title ?? a.feature_details?.movie_name,
                    year: a.feature_details?.year, season: a.feature_details?.season_number,
                    episode: a.feature_details?.episode_number, uploadDate: a.upload_date)
            }
        }
    }

    struct Attributes: Decodable {
        let language: String?
        let download_count: Int?
        let hearing_impaired: Bool?
        let fps: Double?
        let release: String?
        let machine_translated: Bool?
        let ai_translated: Bool?
        let from_trusted: Bool?
        let moviehash_match: Bool?
        let upload_date: String?
        let feature_details: Feature?
        let files: [File]?
    }

    struct Feature: Decodable {
        let title: String?
        let movie_name: String?
        let year: Int?
        let season_number: Int?
        let episode_number: Int?
    }

    struct File: Decodable {
        let file_id: Int?
        let file_name: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? c.decode([Item].self, forKey: .data)) ?? []
    }
    enum CodingKeys: String, CodingKey { case data }
}

private struct LoginResponse: Decodable {
    let token: String?
    let base_url: String?
    let user: User?
    struct User: Decodable { let allowed_downloads: Int? }
}

private struct DownloadResponse: Decodable {
    let link: String?
    let file_name: String?
    let remaining: Int?
}

private struct ErrorResponse: Decodable {
    let message: String?
    let errors: [String]?
    var text: String { message ?? errors?.joined(separator: " ") ?? "" }
}
