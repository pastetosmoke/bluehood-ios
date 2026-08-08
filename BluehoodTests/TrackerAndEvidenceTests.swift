// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftData
import XCTest
@testable import Bluehood

final class TrackerClassifierTests: XCTestCase {

    func testTileByServiceUUID() {
        XCTAssertEqual(TrackerClassifier.classify(makeAdv(serviceUUIDs: ["FEED"])), .tile)
    }

    func testSamsungByServiceUUID() {
        XCTAssertEqual(TrackerClassifier.classify(makeAdv(serviceUUIDs: ["FD5A"])), .samsungSmartTag)
    }

    func testSamsungByCompanyID() {
        XCTAssertEqual(TrackerClassifier.classify(makeAdv(manufacturer: [0x75, 0x00, 0x01])),
                       .samsungSmartTag)
    }

    func testGoogleByServiceUUID() {
        XCTAssertEqual(TrackerClassifier.classify(makeAdv(serviceUUIDs: ["FEAA"])), .googleFindMy)
    }

    /// Apple の offline finding は先頭 0x12。実機のiOSでは届かないが判定自体は保持する
    /// (将来コンパニオン機からの入力を受ける可能性があるため)。
    func testAppleOfflineFindingSignature() {
        XCTAssertEqual(TrackerClassifier.classify(makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19])),
                       .appleFindMy)
    }

    /// Apple でも 0x12 以外はトラッカーではない(iPhoneやAirPodsを誤検知しない)。
    func testAppleNonTrackerPayloadIsNotATracker() {
        XCTAssertNil(TrackerClassifier.classify(makeAdv(manufacturer: [0x4C, 0x00, 0x10, 0x05])))
    }

    func testUnknownIsNotATracker() {
        XCTAssertNil(TrackerClassifier.classify(makeAdv(serviceUUIDs: ["180F"])))
    }

    /// AirTagが検出不能であることを型として持つ。
    /// UIが「0件」と「検出できない」を区別するための根拠になる。
    func testAppleIsMarkedUndetectableOnIOS() {
        XCTAssertFalse(TrackerType.appleFindMy.detectableOnIOS)
        XCTAssertTrue(TrackerType.tile.detectableOnIOS)
        XCTAssertNil(TrackerType.appleFindMy.backgroundServiceUUID,
                     "サービスUUIDを持たないので背景スキャンに列挙できない")
    }

    func testBackgroundUUIDsExcludeApple() {
        let uuids = TrackerClassifier.backgroundScanUUIDs.map(\.uuidString)
        XCTAssertTrue(uuids.contains("FEED"))
        XCTAssertEqual(uuids.count, 3)
    }
}

final class EvidenceTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Sweep.self, SweepDevice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 3地点・日またぎのスイープを作る。
    @MainActor
    private func seed(_ ctx: ModelContext) -> [Sweep] {
        let coords = [(35.6812, 139.7671), (35.6852, 139.7528), (35.7100, 139.8107)]
        var out: [Sweep] = []
        for (i, c) in coords.enumerated() {
            let s = Sweep(label: "場所\(i + 1)")
            s.startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400)
            s.endedAt = s.startedAt.addingTimeInterval(60)
            s.myLat = c.0; s.myLon = c.1; s.myAccuracyM = 20
            let d = SweepDevice(hit: SweepHit(
                stableKey: "KEY-A", firstSeen: s.startedAt, lastSeen: s.startedAt,
                bestRSSI: -55, lastRSSI: -55, count: 4,
                name: "TestDevice", vendor: "Apple", deviceType: nil,
                trackerType: nil, isLowEntropy: false, manufacturerHex: "4c001219"))
            d.sweep = s
            s.devices.append(d)
            ctx.insert(s)
            out.append(s)
        }
        return out
    }

    @MainActor
    func testCoPresenceAcrossThreePlacesIsFlagged() throws {
        let ctx = ModelContext(try makeContainer())
        let sweeps = seed(ctx)

        let results = CoPresenceDetector.analyze(sweeps: sweeps)
        XCTAssertEqual(results.count, 1)
        let r = try XCTUnwrap(results.first)
        XCTAssertEqual(r.sweepCount, 3)
        XCTAssertEqual(r.distinctPlaces, 3)
        XCTAssertTrue(r.spansDays)
        XCTAssertTrue(r.locationKnown)
        XCTAssertGreaterThanOrEqual(r.score, 5.0)
        XCTAssertTrue(r.isConcerning)
    }

    /// 1回しか見えていないものは共起ではない。
    @MainActor
    func testSingleSweepIsNotCoPresence() throws {
        let ctx = ModelContext(try makeContainer())
        let sweeps = seed(ctx)
        XCTAssertTrue(CoPresenceDetector.analyze(sweeps: [sweeps[0]]).isEmpty)
    }

    /// **最重要**: 第三者がハッシュチェーンを再計算できること。
    /// 再現できないチェーンは証拠として無価値なので、決定性をテストで固定する。
    @MainActor
    func testHashChainIsDeterministic() throws {
        let ctx = ModelContext(try makeContainer())
        let sweeps = seed(ctx)
        let co = try XCTUnwrap(CoPresenceDetector.analyze(sweeps: sweeps).first)

        let a = EvidenceExporter.export(co, sweeps: sweeps)
        let b = EvidenceExporter.export(co, sweeps: sweeps)
        XCTAssertEqual(a.chainTip, b.chainTip, "同じ入力から同じチェーンが出ないと検証不能")
        XCTAssertFalse(a.chainTip.isEmpty)
        XCTAssertEqual(a.chainTip.count, 64, "SHA-256は64桁の16進")
    }

    /// 証拠に相手の座標が含まれないこと。設計上の防御線をテストで固定する。
    @MainActor
    func testEvidenceContainsNoTargetLocation() throws {
        let ctx = ModelContext(try makeContainer())
        let sweeps = seed(ctx)
        let co = try XCTUnwrap(CoPresenceDetector.analyze(sweeps: sweeps).first)
        let json = EvidenceExporter.export(co, sweeps: sweeps).json

        XCTAssertTrue(json.contains("my_lat"))
        for banned in ["target_lat", "device_lat", "peer_lat", "their_lat"] {
            XCTAssertFalse(json.contains(banned), "\(banned) が含まれてはいけない")
        }
    }

    /// 出力が「改ざん不可」を主張していないこと。
    /// 過大な主張は、最も助けが必要な場面で梯子を外す。
    @MainActor
    func testEvidenceDoesNotClaimTamperProof() throws {
        let ctx = ModelContext(try makeContainer())
        let sweeps = seed(ctx)
        let co = try XCTUnwrap(CoPresenceDetector.analyze(sweeps: sweeps).first)
        let json = EvidenceExporter.export(co, sweeps: sweeps).json.lowercased()

        XCTAssertFalse(json.contains("tamper-proof"))
        XCTAssertFalse(json.contains("tamper proof"))
        XCTAssertTrue(json.contains("not proof of authenticity"),
                      "何を証明しないかを明示していること")
    }
}
