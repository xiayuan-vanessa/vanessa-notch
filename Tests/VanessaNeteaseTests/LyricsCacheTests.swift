import XCTest
import VanessaCore
@testable import VanessaNetease

final class LyricsCacheTests: XCTestCase {
    private func tmpDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vanessa-cache-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private let sample = Lyrics(lines: [LyricLine(startMs: 0, endMs: 1000, text: "hi", words: [])])

    func test_missReturnsNil() {
        let cache = LyricsCache(directory: tmpDir())
        XCTAssertNil(cache.lyrics(forSongID: 1))
    }

    func test_memoryHitAfterStore() {
        let cache = LyricsCache(directory: tmpDir())
        cache.store(sample, forSongID: 42)
        XCTAssertEqual(cache.lyrics(forSongID: 42), sample)
    }

    func test_diskPersistsAcrossInstances() {
        let dir = tmpDir()
        LyricsCache(directory: dir).store(sample, forSongID: 7)
        let fresh = LyricsCache(directory: dir)
        XCTAssertEqual(fresh.lyrics(forSongID: 7), sample)
    }
}
