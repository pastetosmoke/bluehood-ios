// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreBluetooth
import Foundation

/// スイープ中に集約された1機器分の結果。
struct SweepHit: Identifiable, Equatable {
    let stableKey: String
    var id: String { stableKey }

    var firstSeen: Date
    var lastSeen: Date
    var bestRSSI: Int          // 最大値 = 最接近時。近さの判断に使う
    var lastRSSI: Int
    var count: Int

    var name: String?
    var vendor: String?
    var deviceType: String?
    var trackerType: TrackerType?
    var isLowEntropy: Bool
    var manufacturerHex: String?

    /// 表示名の優先順。名乗る機器はその名前が最も確実な情報。
    var title: String {
        name ?? trackerType?.rawValue ?? vendor ?? String(stableKey.prefix(12))
    }

    /// RSSIから見た近さ。鞄の中・同じ部屋・遠い、程度の粒度に留める。
    /// 距離をメートルで出さないのは、RSSIから距離を出すのが原理的に不正確で、
    /// 「2.3m」のような数字は根拠のない確信を与えるため。
    enum Proximity: String {
        case veryClose = "至近"      // 鞄の中・身につけている距離
        case near      = "近い"      // 同じ部屋
        case far       = "遠い"
    }

    var proximity: Proximity {
        if bestRSSI >= -65 { return .veryClose }
        if bestRSSI >= -85 { return .near }
        return .far
    }
}

/// 前景スイープのスキャナ。
///
/// 前景専用なのは `allowDuplicates` がバックグラウンドで無視されるため。
/// 重複配信が無いとRSSIの推移も広告間隔も取れず、スイープとして成立しない。
/// バックグラウンド監視は別系統(サービスUUID列挙)でフェーズ4に回す。
@MainActor
final class SweepScanner: NSObject, ObservableObject {

    @Published private(set) var state = ScanState()
    @Published private(set) var hits: [SweepHit] = []

    private var central: CBCentralManager!
    private var byKey: [String: SweepHit] = [:]
    private var pendingStart = false          // 電源ON待ちで開始を保留しているか
    private var ticker: Timer?

    override init() {
        super.init()
        // showPowerAlert=false: 電源OFFの説明は自前UIで出し続ける。
        // システムアラートは一度閉じられると消え、後に「動いているつもり」の状態だけが残る。
        central = CBCentralManager(
            delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    // MARK: - 操作

    func start() {
        guard let reason = ScanState.reason(for: central.state) else {
            beginScan(); return
        }
        // まだ状態が確定していないだけなら、確定後に自動で開始する
        pendingStart = (central.state == .unknown || central.state == .resetting)
        state.block(reason)
    }

    func stop() {
        central.stopScan()
        ticker?.invalidate(); ticker = nil
        pendingStart = false
        state.finish()
    }

    private func beginScan() {
        byKey.removeAll()
        hits = []
        pendingStart = false
        state.begin()
        // allowDuplicates: 同一機器の再送も全部受ける。前景でのみ有効。
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        // 経過時間を動かすためだけのタイマー。受信0でも画面が止まって見えないようにする。
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    // MARK: - 集約

    fileprivate func ingest(_ adv: Advertisement) {
        state.received += 1

        let tracker = TrackerClassifier.classify(adv)
        let key = tracker.map { Fingerprint.trackerKey(type: $0, adv: adv) }
            ?? Fingerprint.stableKey(adv)
        let idn = DeviceNamer.identify(adv)

        if var h = byKey[key] {
            h.lastSeen = adv.at
            h.lastRSSI = adv.rssi
            h.bestRSSI = max(h.bestRSSI, adv.rssi)
            h.count += 1
            // 後から分かった素性は補完する。一度読めた名前は保持する。
            h.name       = h.name       ?? idn.name
            h.vendor     = h.vendor     ?? idn.vendor
            h.deviceType = h.deviceType ?? idn.type
            byKey[key] = h
        } else {
            byKey[key] = SweepHit(
                stableKey: key,
                firstSeen: adv.at, lastSeen: adv.at,
                bestRSSI: adv.rssi, lastRSSI: adv.rssi, count: 1,
                name: idn.name, vendor: idn.vendor, deviceType: idn.type,
                trackerType: tracker, isLowEntropy: adv.isLowEntropy,
                manufacturerHex: adv.manufacturerData?.hexString
            )
        }

        state.distinct = byKey.count
        // 近い順に並べる。スイープの目的は「今ここにあるもの」を見つけることなので
        // 電波の強さがそのまま重要度になる。
        hits = byKey.values.sorted { $0.bestRSSI > $1.bestRSSI }
    }
}

extension SweepScanner: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if let reason = ScanState.reason(for: central.state) {
                // スイープ中に電源を切られた場合もここに来る。黙って止まらせない。
                if state.isSweeping { central.stopScan(); ticker?.invalidate(); ticker = nil }
                state.block(reason)
            } else if pendingStart || state.blockedReason != nil {
                // 電源が入った/許可された → 保留していた開始を実行、または待機状態へ戻す
                if pendingStart { beginScan() } else { state.status = .idle }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            // RSSI 127 は「不明」を意味する予約値。距離判定に使うと誤って至近と出る。
            guard RSSI.intValue != 127 else { return }
            ingest(Advertisement(advertisementData: advertisementData, rssi: RSSI.intValue))
        }
    }
}
