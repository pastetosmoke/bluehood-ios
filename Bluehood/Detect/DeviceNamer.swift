// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 広告から読める/類推できる素性。
/// スマートフォンは名前を出さないので vendor 止まり。個体特定はしない。
struct Identity {
    let name: String?      // 広告されたローカル名(あれば最も確実)
    let vendor: String?    // 会社IDからの推定
    let type: String?      // サービスUUIDからの推定
}

enum DeviceNamer {

    static func identify(_ adv: Advertisement) -> Identity {
        Identity(name: adv.localName, vendor: vendor(of: adv), type: type(of: adv))
    }

    /// 会社ID→ベンダー。確度の高いものだけ持ち、未知は "Co.0xNNNN" と正直に返す。
    /// 全社IDを同梱しても、名前を出す機器は既にローカル名で読めるので実利が薄い。
    private static func vendor(of adv: Advertisement) -> String? {
        guard let cid = adv.companyID else { return nil }
        return vendors[cid] ?? String(format: "Co.0x%04X", cid)
    }

    private static func type(of adv: Advertisement) -> String? {
        let shorts = Set(
            (adv.serviceUUIDs.compactMap(\.short16)) + (adv.serviceData.keys.compactMap(\.short16))
        )
        for (uuid, label) in types where shorts.contains(uuid) { return label }
        return nil
    }

    private static let vendors: [UInt16: String] = [
        0x004C: "Apple",
        0x0006: "Microsoft",
        0x00E0: "Google",
        0x0075: "Samsung",
        0x0059: "Nordic",
        0x0157: "Xiaomi/Huami",
    ]

    // 順序が意味を持つので配列で持つ(より具体的なものを先に)
    private static let types: [(UInt16, String)] = [
        (0x1812, "HID(キーボード/マウス)"),
        (0x180D, "心拍/フィットネス"),
        (0xFE2C, "Google Fast Pair"),
        (0xFD5A, "Samsung SmartTag"),
        (0xFEED, "Tile"),
        (0xFEAA, "Eddystone/Google"),
        (0x180F, "バッテリーサービス"),
    ]
}
