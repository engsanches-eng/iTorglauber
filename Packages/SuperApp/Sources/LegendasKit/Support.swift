import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Tradução: as chaves são o texto em português; o catálogo traz o inglês.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .module, comment: ""), arguments: args)
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Acesso mínimo ao Keychain (chave da API, senha e token do OpenSubtitles).
enum LegendaKeychain {
    private static let service = "SuperApp.Legenda"

    static func set(_ value: String?, for key: String) {
        delete(key)
        guard let value, !value.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// Aviso rápido no rodapé da aba Legenda.
@MainActor
final class LegendaToast: ObservableObject {
    static let shared = LegendaToast()
    @Published var message: String?
    private var token = 0

    func show(_ m: String, seconds: Double = 2.6) {
        message = m
        token += 1
        let current = token
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: m)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.token == current else { return }
            self.message = nil
        }
    }
}
