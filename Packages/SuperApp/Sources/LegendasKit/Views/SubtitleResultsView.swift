import SwiftUI

/// Lista de legendas encontradas para um vídeo. Tocar numa legenda baixa e salva.
struct SubtitleResultsView: View {
    let video: FolderItem
    @State var languages: [SubtitleLanguage]
    let onPick: (SubtitleResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var results: [SubtitleResult] = []
    @State private var loading = true
    @State private var error: String?
    @State private var pickingLanguage = false

    private var synced: [SubtitleResult] { results.filter(\.hashMatch) }
    private var byName: [SubtitleResult] { results.filter { !$0.hashMatch } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(video.name, systemImage: "film").font(.subheadline).lineLimit(3)
                    HStack {
                        Text(L("Idioma"))
                        Spacer()
                        Button(languages.map(\.name).joined(separator: " · ")) { pickingLanguage = true }
                    }
                }
                if loading {
                    HStack { Spacer(); ProgressView(L("Buscando legendas…")); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let error {
                    Text(error).foregroundStyle(.red)
                    Button(L("Tentar de novo")) { Task { await load() } }
                } else if results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "captions.bubble").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(L("Nenhuma legenda compatível foi encontrada para este arquivo.")).multilineTextAlignment(.center)
                        Button(L("Buscar em outro idioma")) { pickingLanguage = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                } else {
                    if !synced.isEmpty {
                        Section {
                            ForEach(synced) { r in resultRow(r) }
                        } header: {
                            Text(L("Sincronizadas com este arquivo"))
                        } footer: {
                            Text(L("Encontradas pelo hash do vídeo: o tempo das falas bate com esta versão."))
                        }
                    }
                    if !byName.isEmpty {
                        Section {
                            ForEach(byName) { r in resultRow(r) }
                        } header: {
                            Text(L("Encontradas pelo nome"))
                        } footer: {
                            Text(L("Podem precisar de ajuste de tempo se forem de outra versão do vídeo."))
                        }
                    }
                }
            }
            .navigationTitle(L("Legendas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
            }
            .task { await load() }
            .sheet(isPresented: $pickingLanguage) {
                LanguagePickerView(title: L("Idioma da busca"), selected: languages.first) { lang in
                    pickingLanguage = false
                    languages = [lang]
                    Task { await load() }
                }
            }
        }
    }

    private func resultRow(_ r: SubtitleResult) -> some View {
        Button { onPick(r) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(r.displayTitle).font(.subheadline.weight(.medium)).lineLimit(3).foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Text(r.language.name)
                    Label("\(r.downloads)", systemImage: "arrow.down.circle")
                    if let fps = r.fps { Text(String(format: "%.3g fps", fps)) }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if r.hashMatch { Badge(text: L("Sincronizada"), color: .green) }
                    if r.fromTrusted { Badge(text: L("Confiável"), color: .blue) }
                    if r.hearingImpaired { Badge(text: L("Para surdos"), color: .purple) }
                    if r.machineTranslated || r.aiTranslated { Badge(text: L("Tradução automática"), color: .orange) }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            results = try await LegendaEngine.shared.search(video: video.url, languages: languages)
        } catch {
            self.error = error.localizedDescription
            results = []
        }
        loading = false
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Escolha de um idioma de legenda.
struct LanguagePickerView: View {
    let title: String
    let selected: SubtitleLanguage?
    var allowNone = false
    let onPick: (SubtitleLanguage) -> Void
    var onNone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                if allowNone {
                    Button { onNone?(); dismiss() } label: {
                        HStack { Text(L("Nenhum")).foregroundStyle(.primary); Spacer(); if selected == nil { Image(systemName: "checkmark") } }
                    }
                }
                ForEach(SubtitleLanguage.sortedByName.filter { filter.trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(filter.trimmed) }) { l in
                    Button { onPick(l); dismiss() } label: {
                        HStack {
                            Text(l.name).foregroundStyle(.primary)
                            Spacer()
                            if l == selected { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            .searchable(text: $filter, prompt: L("Buscar idioma"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } } }
        }
    }
}
