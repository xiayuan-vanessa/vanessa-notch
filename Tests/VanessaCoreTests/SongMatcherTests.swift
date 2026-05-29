import XCTest
@testable import VanessaCore

final class SongMatcherTests: XCTestCase {
    private func cand(_ id: Int64, _ t: String, _ a: [String], _ d: Int) -> SongCandidate {
        SongCandidate(id: id, title: t, artists: a, durationMs: d)
    }

    func test_exactMatch_wins() {
        let q = SongQuery(title: "晴天", artist: "周杰伦", durationMs: 269000)
        let c = [cand(1, "晴天", ["周杰伦"], 269000), cand(2, "雨天", ["林俊杰"], 200000)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c)?.id, 1)
    }

    func test_durationToleranceFiltersFarCandidates() {
        let q = SongQuery(title: "歌", artist: "人", durationMs: 200000)
        let c = [cand(1, "歌", ["人"], 230000), cand(2, "歌", ["人"], 201000)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c, durationToleranceMs: 5000)?.id, 2)
    }

    func test_normalizesCasePunctuationAndFeat() {
        let q = SongQuery(title: "Hello (Live)", artist: "Adele feat. someone", durationMs: 100000)
        let c = [cand(1, "hello", ["Adele"], 100500)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c)?.id, 1)
    }

    func test_noConfidentMatch_returnsNil() {
        let q = SongQuery(title: "完全不同的歌名ABC", artist: "某人", durationMs: 100000)
        let c = [cand(1, "毫不相干XYZ", ["另一个人"], 500000)]
        XCTAssertNil(SongMatcher.bestMatch(for: q, in: c))
    }

    func test_emptyCandidates_returnsNil() {
        let q = SongQuery(title: "x", artist: "y", durationMs: 1000)
        XCTAssertNil(SongMatcher.bestMatch(for: q, in: []))
    }
}
