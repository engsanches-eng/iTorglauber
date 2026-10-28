import Foundation

/// Um item mostrado no navegador de pastas.
struct FolderItem: Identifiable, Hashable {
    enum Kind: Hashable { case folder, video, subtitle, other }

    let url: URL
    let name: String
    let kind: Kind
    let size: Int64?
    let modified: Date?
    /// Arquivo do iCloud que ainda não está no aparelho.
    let isCloudPlaceholder: Bool
    var hasSubtitle = false

    var id: String { url.path }
    var baseName: String { (name as NSString).deletingPathExtension }
}

enum FileBrowser {
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "wmv", "mpg", "mpeg", "ts", "m2ts", "webm", "flv", "divx", "rmvb", "3gp", "ogv",
    ]
    static let subtitleExtensions: Set<String> = ["srt", "sub", "ass", "ssa", "vtt"]

    static func kind(for name: String, isDirectory: Bool) -> FolderItem.Kind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if subtitleExtensions.contains(ext) { return .subtitle }
        return .other
    }

    /// Lista uma pasta: pastas primeiro, depois arquivos, em ordem de nome.
    static func list(_ folder: URL) throws -> [FolderItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        var items: [FolderItem] = []
        for u in urls {
            var name = u.lastPathComponent
            var target = u
            var placeholder = false
            // iCloud: arquivo ainda na nuvem aparece como ".Nome.mkv.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                target = u.deletingLastPathComponent().appendingPathComponent(name)
                placeholder = true
            } else if name.hasPrefix(".") {
                continue
            }
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isDir = v?.isDirectory ?? false
            items.append(FolderItem(
                url: target, name: name, kind: kind(for: name, isDirectory: isDir),
                size: v?.fileSize.map(Int64.init), modified: v?.contentModificationDate, isCloudPlaceholder: placeholder))
        }
        // Marca vídeos que já têm legenda com o mesmo nome (Filme.srt ou Filme.pt-BR.srt).
        let subtitleBases = Set(items.filter { $0.kind == .subtitle }.map { $0.baseName.lowercased() })
        for i in items.indices where items[i].kind == .video {
            let base = items[i].baseName.lowercased()
            items[i].hasSubtitle = subtitleBases.contains { $0 == base || $0.hasPrefix(base + ".") }
        }
        return items.sorted {
            if ($0.kind == .folder) != ($1.kind == .folder) { return $0.kind == .folder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Legendas que pertencem a este vídeo (para "Apagar legenda").
    static func subtitles(for video: URL) -> [URL] {
        let folder = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent.lowercased()
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { u in
            let n = u.deletingPathExtension().lastPathComponent.lowercased()
            return subtitleExtensions.contains(u.pathExtension.lowercased()) && (n == base || n.hasPrefix(base + "."))
        }
    }
}

/// Grava a legenda ao lado do vídeo, com o mesmo nome (só a extensão muda).
enum SubtitleWriter {
    enum WriteError: LocalizedError {
        case readOnly, failed(String)
        var errorDescription: String? {
            switch self {
            case .readOnly: return L("Esta pasta não permite gravar arquivos. Escolha outra pasta ou copie o vídeo para o iPhone.")
            case .failed(let m): return L("Não foi possível salvar a legenda: %@", m)
            }
        }
    }

    /// Nome final da legenda, ex.: "Filme.srt" ou "Filme.pt-BR.srt".
    static func targetURL(video: URL, language: SubtitleLanguage, naming: LegendaSettings.Naming) -> URL {
        let base = video.deletingPathExtension().lastPathComponent
        let name = naming == .withLanguage ? "\(base).\(language.fileTag).srt" : "\(base).srt"
        return video.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Alternativa quando já existe uma legenda e o usuário quer manter as duas.
    static func alternativeURL(for url: URL, language: SubtitleLanguage) -> URL {
        let folder = url.deletingLastPathComponent()
        var base = url.deletingPathExtension().lastPathComponent
        let tag = "." + language.fileTag
        if !base.hasSuffix(tag) { base += tag }
        var candidate = folder.appendingPathComponent(base + ".srt")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base).\(n).srt")
            n += 1
        }
        return candidate
    }

    /// Converte para UTF-8 (muitas legendas em português vêm em Windows-1252 e quebrariam os acentos).
    static func normalizedText(_ data: Data) -> Data {
        if String(data: data, encoding: .utf8) != nil { return data }
        if let s = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1),
           let utf8 = s.data(using: .utf8) {
            return utf8
        }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        let text = normalizedText(data)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { dest in
            do { try text.write(to: dest, options: .atomic) } catch { writeError = error }
        }
        if let e = writeError ?? coordError {
            let ns = e as NSError
            if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(ns.code) {
                throw WriteError.readOnly
            }
            throw WriteError.failed(e.localizedDescription)
        }
    }

    static func delete(_ url: URL) throws {
        var coordError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { dest in
            do { try FileManager.default.removeItem(at: dest) } catch { deleteError = error }
        }
        if let e = deleteError ?? coordError { throw e }
    }
}

/// Lê o hash do vídeo com coordenação de arquivos (necessário no iCloud e em provedores de arquivos).
enum CoordinatedHash {
    static func compute(_ url: URL) -> String? {
        var result: String?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &err) { u in
            result = try? VideoHash.compute(url: u)
        }
        return result
    }
}
