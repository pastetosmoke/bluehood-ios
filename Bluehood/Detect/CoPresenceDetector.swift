// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 複数のスイープにまたがって現れた機器。
struct CoPresence: Identifiable {
    let stableKey: String
    var id: String { stableKey }

    let title: String
    let trackerType: TrackerType?
    let sweepCount: Int          // 何回のスイープで見えたか
    let distinctPlaces: Int      // 空間的に独立した地点の数
    let spansDays: Bool
    let bestRSSI: Int            // 全スイープ通じての最接近
    let firstSeen: Date
    let lastSeen: Date
    let score: Double
    let locationKnown: Bool      // 位置が取れていたか(取れていないと判定が弱くなる)

    var isConcerning: Bool { score >= 5.0 }
}

/// スイープ間の共起判定。
///
/// Android版 `StalkerDetector` と**同じ採点式**を使う。
/// 両者が同じパターンに違うスコアを出すと、利用者はどちらを信じればいいか分からなくなる。
///
/// 違うのは文脈の作り方だけ:
///   Android: 連続ログを空間200m / 時間30分で自動分割して文脈にする
///   iOS:     利用者が意図して実行したスイープ1回をそのまま1文脈にする
///
/// 手動になるぶん文脈の独立性はむしろ明確になる。
/// 「自宅で調べた」「ホテルで調べた」は、受動ログの断片より意図がはっきりしている。
enum CoPresenceDetector {

    /// 同一地点とみなす距離。これ以上離れて初めて別の場所として数える。
    static let sameePlaceMeters = 200.0
    /// 日をまたいだとみなす時間差。
    static let spansDaysSeconds = 12.0 * 3600.0
    /// 時間的に非連続とみなす間隔。
    static let nonContiguousSeconds = 30.0 * 60.0

    static func analyze(sweeps: [Sweep]) -> [CoPresence] {
        // stableKey ごとに、どのスイープで見えたかを集める
        var byKey: [String: [(sweep: Sweep, device: SweepDevice)]] = [:]
        for sweep in sweeps {
            // 同一スイープ内の重複は1回として数える(1スイープ=1文脈なので)
            var seenInThisSweep = Set<String>()
            for d in sweep.devices where !seenInThisSweep.contains(d.stableKey) {
                seenInThisSweep.insert(d.stableKey)
                byKey[d.stableKey, default: []].append((sweep, d))
            }
        }

        return byKey.compactMap { key, entries in
            guard entries.count >= 2 else { return nil }   // 1回しか見えていないものは共起ではない
            return build(key: key, entries: entries)
        }
        .sorted { $0.score > $1.score }
    }

    private static func build(key: String,
                              entries: [(sweep: Sweep, device: SweepDevice)]) -> CoPresence {
        let sorted = entries.sorted { $0.sweep.startedAt < $1.sweep.startedAt }
        let located = sorted.filter { $0.sweep.myLat != nil && $0.sweep.myLon != nil }
        let locationKnown = located.count >= 2

        let places = distinctPlaces(located.map { ($0.sweep.myLat!, $0.sweep.myLon!) })

        let times = sorted.map(\.sweep.startedAt)
        let spansDays = (times.last!.timeIntervalSince(times.first!)) > spansDaysSeconds
        let nonContiguous = zip(times, times.dropFirst())
            .filter { $1.timeIntervalSince($0) > nonContiguousSeconds }
            .count

        let sample = sorted.last!.device

        return CoPresence(
            stableKey: key,
            title: sample.title,
            trackerType: sample.trackerType,
            sweepCount: sorted.count,
            distinctPlaces: places,
            spansDays: spansDays,
            bestRSSI: sorted.map(\.device.bestRSSI).max() ?? -127,
            firstSeen: times.first!,
            lastSeen: times.last!,
            score: score(places: places, nonContiguous: nonContiguous,
                         spansDays: spansDays, sweeps: sorted.count,
                         locationKnown: locationKnown),
            locationKnown: locationKnown
        )
    }

    /// Android版と同一の採点式。
    ///
    /// 最初の2地点は加点しない。自宅と職場が同じ同僚、同じ路線の常連 —
    /// 生活圏が重なるだけの相手を尾行と呼ばないための下駄。
    /// 3地点目以降の広がり、時間的な非連続、日またぎが揃って初めて閾値5を超える。
    static func score(places: Int, nonContiguous: Int, spansDays: Bool,
                      sweeps: Int, locationKnown: Bool) -> Double {
        // 位置が取れていない場合、空間的な独立性を検証できない。
        // 「別の場所だった」と主張できないので、スイープ回数だけで低い上限に抑える。
        // ここで通常の点数を出すと、同じ部屋で3回スイープしただけで警告が出る。
        guard locationKnown else {
            return min(Double(sweeps) * 0.5, 3.0)
        }
        guard places >= 3 else { return 0.0 }

        let base = Double(places - 2) * 2.0
            + Double(nonContiguous) * 1.5
            + (spansDays ? 3.0 : 0.0)
        return min(base, 10.0)
    }

    /// 200m以上離れた地点をいくつ通ったか。
    /// 単純なクラスタリングで十分 — 精度より「別の場所と言い切れるか」が問題なので。
    static func distinctPlaces(_ coords: [(Double, Double)]) -> Int {
        var centers: [(Double, Double)] = []
        for c in coords {
            let isNew = centers.allSatisfy { distanceM($0, c) >= sameePlaceMeters }
            if isNew { centers.append(c) }
        }
        return centers.count
    }

    static func distanceM(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6_371_000.0
        let dLat = (b.0 - a.0) * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let lat1 = a.0 * .pi / 180
        let lat2 = b.0 * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
