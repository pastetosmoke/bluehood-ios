// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftData

/// 1回のスイープ = 1つの「文脈」。
///
/// Android版は連続ログから自動で文脈を切り出すが、iOSは前景でしかスキャンできないため
/// 利用者が意図して実行した1回をそのまま1文脈として扱う。
/// 手動になるぶん、文脈の独立性はむしろ明確になる。
@Model
final class Sweep {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var label: String?             // 「レンタカー」「ホテル301」など利用者が付ける

    // 自分の座標のみ。相手の推定座標を保存するフィールドは作らない。
    // これは方針ではなく構造上の防御線 — 列が無ければ書きようがない。
    var myLat: Double?
    var myLon: Double?
    var myAccuracyM: Double?

    var receivedCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \SweepDevice.sweep)
    var devices: [SweepDevice] = []

    init(label: String? = nil) {
        self.startedAt = Date()
        self.label = label
    }

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}

/// スイープ中に観測された1機器。
@Model
final class SweepDevice {
    var stableKey: String = ""
    var firstSeen: Date = Date()
    var lastSeen: Date = Date()
    var bestRSSI: Int = -127
    var count: Int = 0

    var name: String?
    var vendor: String?
    var deviceType: String?
    var trackerTypeRaw: String?
    var isLowEntropy: Bool = false
    var manufacturerHex: String?

    var sweep: Sweep?

    init(hit: SweepHit) {
        stableKey = hit.stableKey
        firstSeen = hit.firstSeen
        lastSeen = hit.lastSeen
        bestRSSI = hit.bestRSSI
        count = hit.count
        name = hit.name
        vendor = hit.vendor
        deviceType = hit.deviceType
        trackerTypeRaw = hit.trackerType?.rawValue
        isLowEntropy = hit.isLowEntropy
        manufacturerHex = hit.manufacturerHex
    }

    var trackerType: TrackerType? { trackerTypeRaw.flatMap(TrackerType.init(rawValue:)) }

    var title: String {
        name ?? trackerTypeRaw ?? vendor ?? String(stableKey.prefix(12))
    }
}
