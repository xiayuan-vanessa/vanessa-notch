import XCTest
import Foundation
@testable import VanessaCore

final class PlaybackClockTests: XCTestCase {
    private func state(elapsed: TimeInterval, rate: Double, playing: Bool,
                       duration: TimeInterval = 300, at t: TimeInterval = 1000) -> NowPlayingState {
        NowPlayingState(title: "t", artist: "a", album: "", artworkData: nil,
                        duration: duration, elapsed: elapsed,
                        sampledAt: Date(timeIntervalSince1970: t),
                        rate: rate, isPlaying: playing, sourceBundleID: "x")
    }

    func test_playingRate1_advancesWithWallClock() {
        let clock = PlaybackClock(state: state(elapsed: 10, rate: 1, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1003))
        XCTAssertEqual(pos, 13000, accuracy: 1)
    }

    func test_rate1_5_advancesFaster() {
        let clock = PlaybackClock(state: state(elapsed: 10, rate: 1.5, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1002))
        XCTAssertEqual(pos, 13000, accuracy: 1)
    }

    func test_paused_doesNotAdvance() {
        let clock = PlaybackClock(state: state(elapsed: 42, rate: 1, playing: false, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 9999))
        XCTAssertEqual(pos, 42000, accuracy: 1)
    }

    func test_clampsToDuration() {
        let clock = PlaybackClock(state: state(elapsed: 295, rate: 1, playing: true, duration: 300, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1100))
        XCTAssertEqual(pos, 300000, accuracy: 1)
    }

    func test_negativeDrift_clampsToZero() {
        let clock = PlaybackClock(state: state(elapsed: 5, rate: 1, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 990))
        XCTAssertEqual(pos, 5000, accuracy: 1)
    }
}
