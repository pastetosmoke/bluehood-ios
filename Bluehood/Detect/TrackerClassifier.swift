// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreBluetooth
import Foundation

/// 検知できる紛失防止タグの種別。
///
/// 個体の特定はしない。DULT/AirGuard と同じく「種別」までで止める。
/// 誰の持ち物かを当てにいくと、対監視ツールがそのまま監視ツールになる。
enum TrackerType: String, CaseIterable {
    case appleFindMy    = "Apple Find My/AirTag"
    case tile           = "Tile"
    case samsungSmartTag = "Samsung SmartTag"
    case googleFindMy   = "Google Find My Device"

    /// iOS でこの種別を実際に検出できるか。
    /// Apple は自社の Find My 広告をサードパーティに渡さないため、AirTag は検出不能。
    /// 「検出なし」と「検出できない」を UI で混同させないための情報。
    var detectableOnIOS: Bool {
        switch self {
        case .appleFindMy: return false
        default:           return true
        }
    }

    /// バックグラウンドで scanForPeripherals(withServices:) に列挙できるか。
    /// サービスUUIDを持たない種別は背景監視の対象にできない。
    var backgroundServiceUUID: CBUUID? {
        switch self {
        case .tile:            return CBUUID(string: "FEED")
        case .samsungSmartTag: return CBUUID(string: "FD5A")
        case .googleFindMy:    return CBUUID(string: "FEAA")
        case .appleFindMy:     return nil
        }
    }
}

enum TrackerClassifier {

    /// 広告の署名から種別を判定する。該当しなければ nil。
    static func classify(_ adv: Advertisement) -> TrackerType? {
        let shorts = Set(
            (adv.serviceUUIDs.compactMap(\.short16)) + (adv.serviceData.keys.compactMap(\.short16))
        )

        if shorts.contains(0xFEED) { return .tile }
        if shorts.contains(0xFD5A) { return .samsungSmartTag }
        if shorts.contains(0xFEAA) { return .googleFindMy }

        if let cid = adv.companyID {
            if cid == 0x0075 { return .samsungSmartTag }
            // Apple: 先頭 0x12 は offline finding = 持ち主から切り離された状態。
            // iOS ではこの広告自体が届かないので、実際にはここに到達しない。
            // Android と同じ判定を残しておくのは、コンパニオン機からの入力を将来受ける可能性のため。
            if cid == 0x004C, adv.manufacturerBody.first == 0x12 { return .appleFindMy }
        }
        return nil
    }

    /// バックグラウンド監視で列挙すべきUUID一覧。
    static var backgroundScanUUIDs: [CBUUID] {
        TrackerType.allCases.compactMap(\.backgroundServiceUUID)
    }
}
