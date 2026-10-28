import Foundation

/// Junta hash, busca, download e gravação — o mesmo caminho do "botão direito" do Legendas no Windows.
@MainActor
final class LegendaEngine {
    static let shared = LegendaEngine()
    private let settings = LegendaSettings.shared

    private var client: OpenSubtitlesClient {
        OpenSubtitlesClient(apiKey: settings.apiKey.trimmed, token: settings.token, host: settings.apiBaseHost)
    }

    // MARK: Busca

    /// Busca legendas para o vídeo nos idiomas pedidos, já ordenadas:
    /// sincronizadas primeiro, depois idioma primário, secundário e número de downloads.
    func search(video: URL, languages: [SubtitleLanguage]) async throws -> [SubtitleResult] {
        guard settings.hasApiKey else { throw OpenSubtitlesError.missingApiKey }
        let hash = await Task.detached(priority: .userInitiated) { CoordinatedHash.compute(video) }.value
        let name = ParsedVideoName.parse(video.lastPathComponent)
        let options = OpenSubtitlesClient.SearchOptions(
            languages: languages,
            includeHearingImpaired: settings.includeHearingImpaired,
            includeMachineTranslated: settings.includeMachineTranslated)
        let results = try await client.search(hash: hash, name: name, options: options)
        return sort(results, languages: languages)
    }

    func sort(_ results: [SubtitleResult], languages: [SubtitleLanguage]) -> [SubtitleResult] {
        func rank(_ l: SubtitleLanguage) -> Int { languages.firstIndex(of: l) ?? languages.count }
        return results.sorted { a, b in
            if a.hashMatch != b.hashMatch { return a.hashMatch }
            if rank(a.language) != rank(b.language) { return rank(a.language) < rank(b.language) }
            if a.fromTrusted != b.fromTrusted { return a.fromTrusted }
            return a.downloads > b.downloads
        }
    }

    /// "Melhor legenda": primário sincronizado, secundário sincronizado, primário por nome, secundário por nome.
    func best(from results: [SubtitleResult]) -> SubtitleResult? {
        let langs = settings.searchLanguages
        for wantHash in [true, false] {
            for l in langs {
                if let r = results.first(where: { $0.hashMatch == wantHash && $0.language == l }) { return r }
            }
        }
        return nil
    }

    // MARK: Download

    /// Baixa e grava a legenda. Devolve o arquivo salvo.
    func downloadAndSave(_ result: SubtitleResult, to target: URL) async throws -> URL {
        guard settings.hasApiKey else { throw OpenSubtitlesError.missingApiKey }
        let downloaded: OpenSubtitlesClient.DownloadResult
        do {
            downloaded = try await client.download(fileId: result.fileId)
        } catch OpenSubtitlesError.server(let code, _) where code == 401 && !settings.password.isEmpty {
            // Token vencido: entra de novo e tenta mais uma vez.
            try await login()
            downloaded = try await client.download(fileId: result.fileId)
        }
        if let r = downloaded.remaining {
            settings.remainingDownloads = r
            settings.remainingUpdatedAt = Date()
        }
        let data = downloaded.data
        try await Task.detached(priority: .userInitiated) { try SubtitleWriter.write(data, to: target) }.value
        return target
    }

    // MARK: Conta

    func login() async throws {
        let user = settings.username.trimmed
        let pass = settings.password
        guard !user.isEmpty, !pass.isEmpty else { throw OpenSubtitlesError.loginFailed(L("Preencha usuário e senha.")) }
        let base = OpenSubtitlesClient(apiKey: settings.apiKey.trimmed)
        let r = try await base.login(username: user, password: pass)
        settings.token = r.token
        settings.apiBaseHost = r.host
        settings.loggedInUser = user
        if let a = r.allowedDownloads, settings.remainingDownloads == nil { settings.remainingDownloads = a; settings.remainingUpdatedAt = Date() }
    }
}
