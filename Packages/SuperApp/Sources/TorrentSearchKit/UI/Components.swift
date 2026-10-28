import SwiftUI
import SafariServices
import WebKit
import UIKit

// MARK: - Categorias

struct CategoryChips: View {
    @Binding var selection: Category
    var categories: [Category]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { c in
                    Button {
                        selection = c
                    } label: {
                        Label(c.title, systemImage: c.systemImage)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selection == c ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            .foregroundStyle(selection == c ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == c ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }
}

extension AppState {
    /// Categorias visíveis (Adulto só aparece com o modo NSFW ligado).
    var visibleCategories: [Category] { Category.allCases.filter { nsfwMode || !$0.isNSFW } }
}

// MARK: - Estado vazio

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message { Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Safari isolado (não compartilha cookies nem histórico com o app)

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController.Configuration()
        c.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: c)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct IdentifiableURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

// MARK: - Compartilhar

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItems: Identifiable { let id = UUID(); let items: [Any] }

// MARK: - Aviso rápido (toast)

final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var message: String?
    func show(_ m: String) {
        message = m
        UIAccessibility.post(notification: .announcement, argument: m)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.message == m { self?.message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @ObservedObject var toast = Toast.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = toast.message {
                Text(m).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toast.message)
    }
}

extension View { func toastOverlay() -> some View { modifier(ToastOverlay()) } }

// MARK: - Abrir magnet no cliente de torrent (ex.: iTorrent)

enum MagnetOpener {
    /// Abre o link magnet. No superapp, vai direto para a aba iTorrent (sem sair do app).
    @MainActor static func open(_ magnet: String) async -> Bool {
        guard let u = URL(string: magnet), u.scheme?.lowercased() == "magnet" else { return false }
        if let handler = BuscaTab.openMagnet { return handler(u) }
        return await UIApplication.shared.open(u)
    }

    static func copy(_ s: String) { UIPasteboard.general.string = s }
}

// MARK: - Desafio do Cloudflare (WebView)

enum CloudflareCookies {
    /// Copia os cookies do WebView para a sessão de rede do app.
    @MainActor static func syncFromWebView(host: String) async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        var found = false
        for c in cookies where host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            HTTPCookieStorage.shared.setCookie(c)
            if c.name == "cf_clearance" { found = true }
        }
        return found
    }

    @MainActor static func clearWebViewData() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}

/// Tela que abre o site no WebView para o usuário passar pela verificação do Cloudflare.
struct CloudflareSolverView: View {
    let provider: SearchProvider
    var onFinish: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var solved = false
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if solved { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } else { ProgressView() }
                    Text(solved ? L("Desafio resolvido!") : L("Resolvendo o desafio do Cloudflare… Se aparecer uma caixa de verificação, toque nela."))
                        .font(.footnote)
                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                WebViewRepresentable(url: URL(string: provider.cloudflareSolverUrl ?? provider.url)!)
            }
            .navigationTitle(provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancelar")) { onFinish(false); dismiss() }
                }
            }
            .task { await poll() }
        }
    }

    private func poll() async {
        let host = URL(string: provider.cloudflareSolverUrl ?? provider.url)?.host ?? ""
        for _ in 0..<180 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            if await CloudflareCookies.syncFromWebView(host: host),
               let challenged = try? await Net.shared.isUrlChallenged(provider.cloudflareSolverUrl ?? provider.url), !challenged {
                solved = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                onFinish(true)
                dismiss()
                return
            }
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = Net.userAgent
        v.load(URLRequest(url: url))
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

// MARK: - Formatação

enum Fmt {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()
    static let date: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static func when(_ d: Date?) -> String? {
        guard let d else { return nil }
        if abs(d.timeIntervalSinceNow) < 30 * 86400 { return relative.localizedString(for: d, relativeTo: Date()) }
        return date.string(from: d)
    }
}

// MARK: - Botão "Concluído" quando a tela abre como folha

struct CloseToolbarButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button(L("Concluído")) { dismiss() } }
}

extension View {
    func closeButton(_ show: Bool) -> some View {
        toolbar { ToolbarItem(placement: .cancellationAction) { if show { CloseToolbarButton() } } }
    }
}
