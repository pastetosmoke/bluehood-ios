// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Bluehood

/// 共起判定の採点。誤検知が出るとユーザーが不必要に怯え、
/// 見逃すと守られていると誤認する。両方向を明示的に固定する。
final class CoPresenceScoreTests: XCTestCase {

    /// 2地点では加点しない。自宅と職場が同じ同僚を尾行と呼ばないため。
    func testTwoPlacesScoresZero() {
        let s = CoPresenceDetector.score(places: 2, nonContiguous: 5, spansDays: true,
                                         sweeps: 5, locationKnown: true)
        XCTAssertEqual(s, 0.0)
    }

    /// 3地点＋日またぎで初めて閾値5に届く。
    func testThreePlacesSpanningDaysCrossesThreshold() {
        let s = CoPresenceDetector.score(places: 3, nonContiguous: 0, spansDays: true,
                                         sweeps: 3, locationKnown: true)
        XCTAssertEqual(s, 5.0, accuracy: 0.001)   // (3-2)*2 + 0 + 3
        XCTAssertGreaterThanOrEqual(s, 5.0)
    }

    /// 3地点でも同日・連続ならまだ届かない。1回の外出に同乗しただけの相手を弾く。
    func testThreePlacesSameDayContiguousStaysBelowThreshold() {
        let s = CoPresenceDetector.score(places: 3, nonContiguous: 0, spansDays: false,
                                         sweeps: 3, locationKnown: true)
        XCTAssertLessThan(s, 5.0)
    }

    /// 位置が無いときは上限3.0。空間の独立性を検証できないため。
    /// ここが効かないと、同じ部屋で3回スイープしただけで警告が出る。
    func testWithoutLocationScoreIsCapped() {
        let s = CoPresenceDetector.score(places: 99, nonContiguous: 99, spansDays: true,
                                         sweeps: 99, locationKnown: false)
        XCTAssertLessThanOrEqual(s, 3.0)
        XCTAssertLessThan(s, 5.0, "位置が無い状態で警告を出してはいけない")
    }

    /// 上限は10。
    func testScoreIsCappedAtTen() {
        let s = CoPresenceDetector.score(places: 50, nonContiguous: 50, spansDays: true,
                                         sweeps: 50, locationKnown: true)
        XCTAssertEqual(s, 10.0)
    }
}

final class DistinctPlacesTests: XCTestCase {

    /// 同じ場所での複数回は1地点。
    func testSameLocationCountsOnce() {
        let n = CoPresenceDetector.distinctPlaces([
            (35.6812, 139.7671), (35.6813, 139.7672), (35.6811, 139.7670),
        ])
        XCTAssertEqual(n, 1)
    }

    /// 200m以上離れれば別地点。東京駅と皇居(約1.5km)。
    func testFarLocationsCountSeparately() {
        let n = CoPresenceDetector.distinctPlaces([
            (35.6812, 139.7671), (35.6852, 139.7528),
        ])
        XCTAssertEqual(n, 2)
    }

    /// 距離計算の健全性。東京-大阪は約400km。
    func testDistanceIsRoughlyCorrect() {
        let d = CoPresenceDetector.distanceM((35.6812, 139.7671), (34.7025, 135.4959))
        XCTAssertEqual(d, 400_000, accuracy: 40_000)
    }

    func testEmptyGivesZero() {
        XCTAssertEqual(CoPresenceDetector.distinctPlaces([]), 0)
    }
}
