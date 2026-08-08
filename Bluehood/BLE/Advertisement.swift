// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreBluetooth
import Foundation

/// 1回の `didDiscover` で観測できた広告の中身。
///
/// iOS は生の AD ストリームを渡さずパース済みの辞書だけを渡すが、
/// 製造者固有データだけは生バイト列で取れる。指紋の主材料はここ。
struct Advertisement {
    let manufacturerData: Data?
    let serviceUUIDs: [CBUUID]
    let serviceData: [CBUUID: Data]
    let txPower: Int?
    let localName: String?
    let rssi: Int
    let at: Date

    /// 製造者固有データ先頭2バイトの会社ID(リトルエンディアン)。
    var companyID: UInt16? {
        guard let m = manufacturerData, m.count >= 2 else { return nil }
        return UInt16(m[m.startIndex]) | (UInt16(m[m.startIndex + 1]) << 8)
    }

    /// 会社IDを除いた製造者データ本体。
    var manufacturerBody: Data {
        guard let m = manufacturerData, m.count > 2 else { return Data() }
        return Data(m.dropFirst(2))
    }

    /// 匿名化が効いていて名寄せの手がかりが無い広告。
    /// Android版と同じ判定: サービスUUID・製造者データ・サービスデータがすべて空。
    var isLowEntropy: Bool {
        serviceUUIDs.isEmpty && (manufacturerData?.isEmpty ?? true) && serviceData.isEmpty
    }

    init(advertisementData: [String: Any], rssi: Int, at: Date = Date()) {
        manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        serviceUUIDs     = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        serviceData      = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        txPower          = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        localName        = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?
                              .trimmingCharacters(in: .whitespacesAndNewlines)
                              .nilIfEmpty
        self.rssi = rssi
        self.at = at
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension CBUUID {
    /// 16bit の短縮UUID。標準サービスの照合に使う。128bit の独自UUIDなら nil。
    var short16: UInt16? {
        let s = uuidString
        guard s.count == 4, let v = UInt16(s, radix: 16) else { return nil }
        return v
    }
}
