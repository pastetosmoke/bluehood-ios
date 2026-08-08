// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation

/// MACではなく広告の中身から安定キーを作る。
///
/// BLEのMACは約15分で回転するが、広告に載る「何者であるか」を示す部分は回転しない。
/// そこを束ねてハッシュすれば、MACが変わっても同一性を追える。
///
/// Android版との差: **PHYが取れない**ため入力が1つ少ない。
/// 値が一致しないので `v2-ios` をキーに埋め、混同を構造で防ぐ。
/// Android の証拠とiOSの証拠を突き合わせる場合は、キーではなく生の製造者データで照合すること。
enum Fingerprint {

    static let version = "v2-ios"

    static func stableKey(_ adv: Advertisement) -> String {
        var parts: [String] = [version]

        parts.append(adv.serviceUUIDs.map(\.uuidString).sorted().joined(separator: ","))

        if let cid = adv.companyID {
            parts.append(String(format: "%04X", cid))
            parts.append(stablePrefix(companyID: cid, body: adv.manufacturerBody).hexString)
        } else {
            parts.append("-")
            parts.append("-")
        }

        parts.append(adv.serviceData.keys.map(\.uuidString).sorted().joined(separator: ","))
        parts.append(adv.txPower.map(String.init) ?? "-")

        return sha256(parts.joined(separator: "|"))
    }

    /// ベンダーごとに「回転しない先頭部分」の長さが違う。
    /// 長く取りすぎると回転するカウンタまで含めてしまい、同一機器が毎回別キーになる。
    /// 短すぎると別機器が同じキーに潰れる。値はAndroid版と揃える。
    private static func stablePrefix(companyID: UInt16, body: Data) -> Data {
        let n: Int
        switch companyID {
        case 0x004C: n = 2      // Apple: type + length までが安定
        case 0x0006: n = 1      // Microsoft
        case 0x00E0: n = 0      // Google: 安定部が無い
        default:     n = 6
        }
        return Data(body.prefix(n))
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// トラッカーは種別＋ペイロード安定部でウィンドウ内の個体として扱う。
    /// 先頭(type/len)と末尾(status/hint)は変動するので落とす。
    static func trackerKey(type: TrackerType, adv: Advertisement) -> String {
        let body = adv.manufacturerBody
        let stable = body.count > 2 ? Data(body.dropLast(1)) : body
        return sha256("TRACKER:\(type.rawValue):\(stable.hexString)")
    }
}
