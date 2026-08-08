// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreBluetooth
import XCTest
@testable import Bluehood

/// 広告辞書を組み立てるヘルパ。CoreBluetooth が渡してくる形をそのまま模す。
func makeAdv(manufacturer: [UInt8]? = nil,
             serviceUUIDs: [String] = [],
             serviceData: [String: [UInt8]] = [:],
             txPower: Int? = nil,
             localName: String? = nil,
             rssi: Int = -60) -> Advertisement {
    var d: [String: Any] = [:]
    if let m = manufacturer { d[CBAdvertisementDataManufacturerDataKey] = Data(m) }
    if !serviceUUIDs.isEmpty {
        d[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs.map { CBUUID(string: $0) }
    }
    if !serviceData.isEmpty {
        var sd: [CBUUID: Data] = [:]
        for (k, v) in serviceData { sd[CBUUID(string: k)] = Data(v) }
        d[CBAdvertisementDataServiceDataKey] = sd
    }
    if let t = txPower { d[CBAdvertisementDataTxPowerLevelKey] = NSNumber(value: t) }
    if let n = localName { d[CBAdvertisementDataLocalNameKey] = n }
    return Advertisement(advertisementData: d, rssi: rssi, at: Date(timeIntervalSince1970: 1_700_000_000))
}

final class FingerprintTests: XCTestCase {

    /// 会社IDはリトルエンディアン。ここを取り違えると全ベンダー判定が崩れる。
    func testCompanyIDIsLittleEndian() {
        let adv = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x34])
        XCTAssertEqual(adv.companyID, 0x004C)          // Apple
        XCTAssertEqual(Array(adv.manufacturerBody), [0x12, 0x34])
    }

    /// RSSI は指紋に含めない。含めると距離が変わるたび別機器として数えてしまう。
    func testKeyIsStableAcrossRSSIChange() {
        let a = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19, 0xAA], rssi: -40)
        let b = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19, 0xAA], rssi: -90)
        XCTAssertEqual(Fingerprint.stableKey(a), Fingerprint.stableKey(b))
    }

    /// Apple は先頭2バイトだけが安定。それ以降が変わっても同一機器と見なせること。
    /// ここが長すぎると、回転するカウンタを拾って毎回別キーになる。
    func testAppleRotatingPayloadKeepsSameKey() {
        let a = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19, 0x01, 0x02, 0x03])
        let b = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19, 0xFF, 0xEE, 0xDD])
        XCTAssertEqual(Fingerprint.stableKey(a), Fingerprint.stableKey(b))
    }

    /// 逆に、安定部が違えば別キーでなければならない。
    func testDifferentStablePrefixGivesDifferentKey() {
        let a = makeAdv(manufacturer: [0x4C, 0x00, 0x12, 0x19])
        let b = makeAdv(manufacturer: [0x4C, 0x00, 0x10, 0x05])
        XCTAssertNotEqual(Fingerprint.stableKey(a), Fingerprint.stableKey(b))
    }

    /// ベンダーが違えば当然別キー。
    func testDifferentVendorGivesDifferentKey() {
        let apple = makeAdv(manufacturer: [0x4C, 0x00, 0x12])
        let ms    = makeAdv(manufacturer: [0x06, 0x00, 0x12])
        XCTAssertNotEqual(Fingerprint.stableKey(apple), Fingerprint.stableKey(ms))
    }

    /// サービスUUIDの並び順で結果が変わってはいけない(広告ごとに順序は保証されない)。
    func testServiceUUIDOrderDoesNotMatter() {
        let a = makeAdv(serviceUUIDs: ["FEED", "180F"])
        let b = makeAdv(serviceUUIDs: ["180F", "FEED"])
        XCTAssertEqual(Fingerprint.stableKey(a), Fingerprint.stableKey(b))
    }

    /// Android版と混同しないためのバージョン印。
    func testKeyCarriesPlatformVersion() {
        XCTAssertEqual(Fingerprint.version, "v2-ios")
    }

    /// 手がかりが何も無い広告は匿名化扱い。
    func testLowEntropyDetection() {
        XCTAssertTrue(makeAdv().isLowEntropy)
        XCTAssertFalse(makeAdv(manufacturer: [0x4C, 0x00]).isLowEntropy)
        XCTAssertFalse(makeAdv(serviceUUIDs: ["FEED"]).isLowEntropy)
    }

    /// 16bit短縮UUIDだけを short16 として扱うこと(128bit独自UUIDは nil)。
    func testShort16OnlyMatchesSixteenBitUUIDs() {
        XCTAssertEqual(CBUUID(string: "FEED").short16, 0xFEED)
        XCTAssertNil(CBUUID(string: "12345678-1234-1234-1234-123456789ABC").short16)
    }
}
