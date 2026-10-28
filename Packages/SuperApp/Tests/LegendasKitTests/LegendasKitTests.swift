import XCTest
@testable import LegendasKit

final class LegendasKitTests: XCTestCase {
    /// Vetor de teste oficial do OpenSubtitles: breakdance.avi (12.909.756 bytes) → 8e245d9679d31e12.
    /// Aqui usamos um caso sintético conferido à mão: só zeros → o hash é o próprio tamanho.
    func testHashOfZerosIsSize() {
        let zeros = Data(count: VideoHash.chunkSize)
        XCTAssertEqual(VideoHash.hash(size: 131_072, head: zeros, tail: zeros), "0000000000020000")
    }

    func testHashSumsLittleEndianWords() {
        var head = Data(count: VideoHash.chunkSize)
        head[0] = 0x01 // primeiro inteiro = 1
        var tail = Data(count: VideoHash.chunkSize)
        tail[8] = 0x02 // segundo inteiro = 2
        XCTAssertEqual(VideoHash.hash(size: 0x10000, head: head, tail: tail), "0000000000010003")
    }

    func testHashWrapsOnOverflow() {
        var head = Data(count: VideoHash.chunkSize)
        for i in 0..<8 { head[i] = 0xFF } // 0xFFFFFFFFFFFFFFFF
        let tail = Data(count: VideoHash.chunkSize)
        XCTAssertEqual(VideoHash.hash(size: 2, head: head, tail: tail), "0000000000000001")
    }

    func testParseEpisode() {
        let p = ParsedVideoName.parse("The.Last.of.Us.S02E03.1080p.WEB.H264-GRP.mkv")
        XCTAssertEqual(p.query, "The Last of Us")
        XCTAssertEqual(p.season, 2)
        XCTAssertEqual(p.episode, 3)
    }

    func testParseMovieWithYear() {
        let p = ParsedVideoName.parse("Cidade.de.Deus.2002.1080p.BluRay.x264.mkv")
        XCTAssertEqual(p.query, "Cidade de Deus")
        XCTAssertEqual(p.year, 2002)
        XCTAssertNil(p.season)
    }

    func testParseMovieWithoutYear() {
        let p = ParsedVideoName.parse("Some_Movie_1080p_WEB-DL.mp4")
        XCTAssertEqual(p.query, "Some Movie")
    }

    func testParseAltEpisodeFormat() {
        let p = ParsedVideoName.parse("Friends 3x07 Dublado.avi")
        XCTAssertEqual(p.query, "Friends")
        XCTAssertEqual(p.season, 3)
        XCTAssertEqual(p.episode, 7)
    }

    func testWindows1252ConvertedToUTF8() {
        let latin = "Ação".data(using: .windowsCP1252)!
        let out = SubtitleWriter.normalizedText(latin)
        XCTAssertEqual(String(data: out, encoding: .utf8), "Ação")
    }

    func testTargetNames() {
        let v = URL(fileURLWithPath: "/tmp/x/Filme.2020.mkv")
        XCTAssertEqual(SubtitleWriter.targetURL(video: v, language: .portugueseBR, naming: .plain).lastPathComponent, "Filme.2020.srt")
        XCTAssertEqual(SubtitleWriter.targetURL(video: v, language: .portugueseBR, naming: .withLanguage).lastPathComponent, "Filme.2020.pt-BR.srt")
    }
}

final class EmbeddedKeyTests: XCTestCase {
    // Vetor de teste com senha descartável ("teste"), gerado fora do app.
    let blob = EmbeddedKey.Blob(salt: "4xEggZLkeiEcmf/p257qWg==",
                                sealed: "keK44K7pAaYIhJAQWr+Y4nYQV5s7hVwnJ7pLDA/CRIHo+51hxKjvI0Lf",
                                iterations: 1000)

    func testCorrectPasswordOpens() {
        XCTAssertEqual(EmbeddedKey.unlock(blob, password: "teste"), "chave-de-teste")
    }

    func testWrongPasswordFails() {
        XCTAssertNil(EmbeddedKey.unlock(blob, password: "Teste"))
        XCTAssertNil(EmbeddedKey.unlock(blob, password: ""))
        XCTAssertNil(EmbeddedKey.unlock(EmbeddedKey.openSubtitles, password: "senha-errada"))
    }
}
