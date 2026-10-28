import Foundation

/// Hash de vídeo usado pelo OpenSubtitles (o mesmo tipo de "impressão digital" do Legendas do Windows):
/// tamanho do arquivo + soma dos primeiros e dos últimos 64 KiB, lidos como inteiros de 64 bits
/// little-endian, com estouro descartado. Lê só 128 KiB, então é rápido até em pastas de rede.
enum VideoHash {
    static let chunkSize = 65_536

    enum HashError: Error { case tooSmall, unreadable }

    static func compute(url: URL) throws -> String {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw HashError.unreadable }
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        guard size >= UInt64(chunkSize) else { throw HashError.tooSmall }

        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: chunkSize), head.count == chunkSize else { throw HashError.unreadable }
        try handle.seek(toOffset: size - UInt64(chunkSize))
        guard let tail = try handle.read(upToCount: chunkSize), tail.count == chunkSize else { throw HashError.unreadable }

        return hash(size: size, head: head, tail: tail)
    }

    /// Parte pura (sem disco), separada para poder ser testada.
    static func hash(size: UInt64, head: Data, tail: Data) -> String {
        var h = size
        for chunk in [head, tail] {
            chunk.withUnsafeBytes { raw in
                let n = raw.count / 8
                for i in 0..<n {
                    let v = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)
                    h = h &+ UInt64(littleEndian: v)
                }
            }
        }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}
