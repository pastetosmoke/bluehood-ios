// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation

/// 証拠パッケージ。追跡ではなく記録。
///
/// 出力は「自分がいつ・どこで・この指紋と共起したか」の連続性だけ。
/// 相手の推定座標は一切含まれない(そもそもデータベースに持っていない)。
///
/// ハッシュチェーンについて正確に:
/// これが証明するのは**内部の整合性**であって、真正性ではない。
/// アプリを持っている者なら誰でも任意の系列を作って正しいチェーンを計算できる。
/// 外部の時刻認証(RFC 3161)を付けるまで「改ざん不可」とは名乗らない。
/// 出力にもその旨を明記する — 読んだ人が過大評価すると、
/// 最も助けが必要な場面で梯子を外されることになる。
enum EvidenceExporter {

    static let schema = "bluehood.evidence.v1"

    struct Package {
        let json: String
        let chainTip: String
        let summary: Summary
    }

    struct Summary {
        let title: String
        let trackerType: String?
        let score: Double
        let sweepCount: Int
        let distinctPlaces: Int
        let locationKnown: Bool
        let firstSeen: Date
        let lastSeen: Date
        let events: [Event]
    }

    struct Event {
        let at: Date
        let label: String?
        let lat: Double?
        let lon: Double?
        let accuracyM: Double?
        let rssi: Int
        let hash: String
    }

    /// 共起した機器1件を、その機器が現れた各スイープの列として書き出す。
    static func export(_ co: CoPresence, sweeps: [Sweep]) -> Package {
        // この指紋が現れたスイープだけを時系列で拾う
        let relevant = sweeps
            .filter { $0.devices.contains { $0.stableKey == co.stableKey } }
            .sorted { $0.startedAt < $1.startedAt }

        var events: [[String: Any]] = []
        var display: [Event] = []
        var prev = "genesis"

        for s in relevant {
            let dev = s.devices.first { $0.stableKey == co.stableKey }
            var ev: [String: Any] = [
                "ts": Int(s.startedAt.timeIntervalSince1970 * 1000),
                "ts_iso": iso8601(s.startedAt),
                "sweep_label": s.label ?? NSNull(),
                // 自分の座標のみ。相手の座標ではない。
                "my_lat": s.myLat ?? NSNull(),
                "my_lon": s.myLon ?? NSNull(),
                "accuracy_m": s.myAccuracyM ?? NSNull(),
                "rssi": dev?.bestRSSI ?? 0,
                "raw_manufacturer": dev?.manufacturerHex ?? NSNull(),
                "prev": prev,
            ]
            prev = sha256(canonical(ev))     // 改ざん検出用チェーン
            ev["hash"] = prev
            events.append(ev)

            display.append(Event(
                at: s.startedAt, label: s.label,
                lat: s.myLat, lon: s.myLon, accuracyM: s.myAccuracyM,
                rssi: dev?.bestRSSI ?? 0, hash: prev
            ))
        }

        let root: [String: Any] = [
            "schema": schema,
            "platform": "ios",
            "unit": "sweep",   // Android版は連続観測単位。単位が違うことを明示する
            "note": "self-centered co-presence log; contains reporter's own GPS only",
            "integrity_note": "The hash chain proves internal consistency only. "
                + "It is NOT proof of authenticity: anyone with this app can construct "
                + "an arbitrary sequence with a valid chain. No external timestamp authority "
                + "has attested to this data.",
            "fingerprint_key": co.stableKey,
            "fingerprint_version": Fingerprint.version,
            "tracker_type": co.trackerType?.rawValue ?? NSNull(),
            "score": co.score,
            "score_note": "Heuristic 0-10. Not a legal determination.",
            "sweep_count": co.sweepCount,
            "distinct_places": co.locationKnown ? co.distinctPlaces : NSNull(),
            "location_available": co.locationKnown,
            "first_seen_iso": iso8601(co.firstSeen),
            "last_seen_iso": iso8601(co.lastSeen),
            "generated_at_iso": iso8601(Date()),
            "timezone": TimeZone.current.identifier,
            "events": events,
            "chain_tip": prev,
        ]

        let json = (try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return Package(
            json: json,
            chainTip: prev,
            summary: Summary(
                title: co.title, trackerType: co.trackerType?.rawValue, score: co.score,
                sweepCount: co.sweepCount, distinctPlaces: co.distinctPlaces,
                locationKnown: co.locationKnown,
                firstSeen: co.firstSeen, lastSeen: co.lastSeen, events: display
            )
        )
    }

    // MARK: - 内部

    /// ハッシュ対象の正規化。キー順が変わるとチェーンが再現できなくなるため、
    /// 辞書順に固定してから連結する。JSONSerialization の出力順に依存させない。
    private static func canonical(_ dict: [String: Any]) -> String {
        dict.keys.sorted().map { k in
            let v = dict[k]!
            let s: String
            switch v {
            case is NSNull: s = "null"
            case let d as Double: s = String(d)
            case let i as Int: s = String(i)
            default: s = String(describing: v)
            }
            return "\(k)=\(s)"
        }.joined(separator: ";")
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
}
