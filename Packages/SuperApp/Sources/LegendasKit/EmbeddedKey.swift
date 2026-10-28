import Foundation
import CryptoKit
import CommonCrypto

/// Chave da API do OpenSubtitles guardada no app de forma criptografada.
/// Só abre com a senha do dono: PBKDF2-SHA256 (600 mil rodadas) gera a chave AES-256-GCM.
/// A senha não fica no código; depois de aberta, a chave vai para o Keychain do iPhone.
enum EmbeddedKey {
    struct Blob {
        let salt: String      // base64
        let sealed: String    // base64: nonce (12) + texto cifrado + tag (16)
        let iterations: UInt32
    }

    static let openSubtitles = Blob(
        salt: "Q9cIOiN/hVHmmzavC9zSdw==",
        sealed: "JSSb1498OnfJjHs8zuKtL5XqqSHRWcWtXzSoWbI3yctdCFkEeQ7HXVxvV32YC7v+GQWlZkdoSkxk1Iaj",
        iterations: 600_000)

    /// Devolve a chave se a senha estiver certa; nil se estiver errada.
    static func unlock(_ blob: Blob, password: String) -> String? {
        guard !password.isEmpty,
              let salt = Data(base64Encoded: blob.salt),
              let sealed = Data(base64Encoded: blob.sealed),
              let key = deriveKey(password: password, salt: salt, iterations: blob.iterations),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) -> SymmetricKey? {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { s -> Int32 in
            pw.withUnsafeBufferPointer { p -> Int32 in
                p.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pw.count) { pp in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), pp, pw.count,
                        s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                        &out, out.count)
                }
            }
        }
        guard status == Int32(kCCSuccess) else { return nil }
        return SymmetricKey(data: out)
    }
}
