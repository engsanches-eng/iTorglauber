import SwiftUI

// MARK: - Linha da lista

struct TorrentRow: View {
    let torrent: Torrent
    var viewed = false
    var bookmarked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(torrent.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(viewed ? .secondary : .primary)
                .lineLimit(3)
            HStack(spacing: 10) {
                if let s = torrent.size { Label(s, systemImage: "internaldrive").labelStyle(.titleAndIcon) }
                if let se = torrent.seeders {
                    Label("\(se)", systemImage: "arrow.up.circle").foregroundStyle(se > 0 ? Color.green : Color.secondary)
                        .accessibilityLabel(L("%ld seeders", se))
                }
                if let p = torrent.peers {
                    Label("\(p)", systemImage: "arrow.down.circle").foregroundStyle(.orange)
                        .accessibilityLabel(L("%ld peers", p))
                }
                if let w = Fmt.when(torrent.uploadDate) { Label(w, systemImage: "calendar") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabel())
            HStack(spacing: 6) {
                Text(torrent.providerName).font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                if let c = torrent.category, c != .all {
                    Text(c.title).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                if torrent.isNSFW { Text("NSFW").font(.caption2.bold()).foregroundStyle(.red) }
                if torrent.isDead { Text(L("Sem fontes")).font(.caption2).foregroundStyle(.red) }
                Spacer()
                if bookmarked { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

// MARK: - Ações do torrent (equivale ao TorrentActionsBottomSheet)

struct TorrentActionsSheet: View {
    let torrent: Torrent
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    enum MagnetState { case loading, ready(String), failed(String) }
    @State private var magnet: MagnetState = .loading
    @State private var fileState: String?
    @State private var safari: IdentifiableURL?
    @State private var share: ShareItems?
    @State private var noClientAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(torrent.name).font(.headline).textSelection(.enabled)
                    info(L("Tamanho"), torrent.size)
                    info(L("Seeders"), torrent.seeders.map(String.init))
                    info(L("Peers"), torrent.peers.map(String.init))
                    info(L("Data de envio"), torrent.uploadDate.map { Fmt.date.string(from: $0) })
                    info(L("Buscador"), torrent.providerName)
                    info(L("Categoria"), torrent.category.map(\.title))
                    if case .ready(let m) = magnet, let h = TorrentUtils.infoHash(m) {
                        Button { MagnetOpener.copy(h); Toast.shared.show(L("Info hash copiado")) } label: {
                            LabeledContent(L("Info hash"), value: h).font(.caption.monospaced())
                        }.foregroundStyle(.primary)
                    }
                }

                Section(L("Link magnet")) {
                    switch magnet {
                    case .loading:
                        HStack { ProgressView(); Text(L("Obtendo o link…")).foregroundStyle(.secondary) }
                    case .failed(let e):
                        Label(L("Não foi possível obter o link"), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        Text(e).font(.caption).foregroundStyle(.secondary)
                        Button(L("Tentar de novo")) { Task { await loadMagnet() } }
                    case .ready(let m):
                        Button {
                            Task { if await MagnetOpener.open(m) { dismiss() } else { noClientAlert = true } }
                        } label: { Label(L("Baixar no iTorrent"), systemImage: "arrow.down.circle") }
                        Button { MagnetOpener.copy(m); Toast.shared.show(L("Link magnet copiado!")) } label: {
                            Label(L("Copiar link magnet"), systemImage: "doc.on.doc")
                        }
                        Button { share = ShareItems(items: [m]) } label: { Label(L("Compartilhar link magnet"), systemImage: "square.and.arrow.up") }
                    }
                }

                Section {
                    Button { Task { await downloadFile() } } label: {
                        Label(L("Baixar arquivo .torrent"), systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(fileState == L("Baixando…"))
                    if let fileState { Text(fileState).font(.caption).foregroundStyle(.secondary) }
                } header: { Text(L("Arquivo torrent")) } footer: {
                    if torrent.fileDownloadLink == nil {
                        Text(L("Este buscador não fornece o arquivo; o app tenta obtê-lo no itorrents.net pelo info hash."))
                    }
                }

                if let details = torrent.detailsPageUrl, let u = URL(string: details) {
                    Section(L("Página de detalhes")) {
                        Button { safari = IdentifiableURL(url: u) } label: { Label(L("Abrir no navegador"), systemImage: "safari") }
                        Button { MagnetOpener.copy(details); Toast.shared.show(L("Link copiado!")) } label: {
                            Label(L("Copiar link da página"), systemImage: "link")
                        }
                        Button { share = ShareItems(items: [u]) } label: { Label(L("Compartilhar link da página"), systemImage: "square.and.arrow.up") }
                    }
                }

                Section {
                    Button { app.toggleBookmark(torrent) } label: {
                        app.isBookmarked(torrent)
                            ? Label(L("Remover dos favoritos"), systemImage: "bookmark.slash")
                            : Label(L("Adicionar aos favoritos"), systemImage: "bookmark")
                    }
                }
            }
            .navigationTitle(L("Torrent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Concluído")) { dismiss() } } }
            .task { app.markViewed(torrent); await loadMagnet() }
            .sheet(item: $safari) { SafariView(url: $0.url).ignoresSafeArea() }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .alert(L("Não foi possível abrir o link"), isPresented: $noClientAlert) {
                Button(L("Copiar link magnet")) { if case .ready(let m) = magnet { MagnetOpener.copy(m) } }
                Button(L("OK"), role: .cancel) {}
            } message: {
                Text(L("O link magnet parece inválido. Copie o link e tente adicionar pela aba iTorrent."))
            }
        }
        .toastOverlay()
    }

    @ViewBuilder private func info(_ label: String, _ value: String?) -> some View {
        if let value { LabeledContent(label, value: value) }
    }

    private func loadMagnet() async {
        switch torrent.magnetUri {
        case .available(let m): magnet = .ready(m)
        case .requiresFetch(let u):
            magnet = .loading
            guard let p = app.builtin.first(where: { $0.name == torrent.providerName }) as? MagnetUriProvider else {
                magnet = .failed(L("Buscador não encontrado")); return
            }
            do { magnet = .ready(try await p.getMagnetUri(url: u)) }
            catch {
                if error is CloudflareChallengeError { app.lockProvider(p.id) }
                magnet = .failed(SearchService.describe(error))
            }
        }
    }

    private func downloadFile() async {
        fileState = L("Baixando…")
        var result: TorrentFileDownloader.Result = .notFound
        if let link = torrent.fileDownloadLink { result = await TorrentFileDownloader.download(link) }
        if case .success = result {} else if case .ready(let m) = magnet, let h = TorrentUtils.infoHash(m) {
            result = await TorrentFileDownloader.downloadUsingInfoHash(h)
        }
        switch result {
        case .success(let data):
            let safeName = torrent.name.replacingOccurrences(of: "/", with: "-").prefix(100)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).torrent")
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                fileState = L("Download concluído")
                share = ShareItems(items: [url])
            } catch { fileState = L("Falha ao salvar") }
        case .notFound: fileState = L("Não encontrado em nenhuma fonte")
        case .failed: fileState = L("Falha no download")
        }
    }
}
