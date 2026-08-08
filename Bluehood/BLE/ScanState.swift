// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreBluetooth
import Foundation

/// スイープの生存状態。ScannerとUIで共有する唯一の真実。
///
/// 護身ツールの最悪の失敗は「守られていると誤認させること」。
/// スキャンが死んでいる状態と、スキャンは生きていて何も見つかっていない状態は、
/// 画面上で絶対に同じに見えてはならない。
///
/// iOS固有の事情: `CBCentralManagerOptionShowPowerAlertKey` を false にして
/// システムの電源アラートを止めているため、電源OFFの説明はこの状態から生成する自前UIが担う。
/// システム任せにすると、アラートを一度閉じられた後に何の痕跡も残らない。
struct ScanState: Equatable {

    enum Status: Equatable {
        case idle                 // まだ開始していない
        case sweeping             // 実際にスイープ中
        case blocked(String)      // 前提条件が欠けている(BT OFF・未許可など)
        case finished             // 完了して結果がある
    }

    var status: Status = .idle
    var received: Int = 0             // 受信した広告の総数。生存の証拠として数字で見せる
    var distinct: Int = 0             // 指紋の異なる機器数
    var startedAt: Date?

    var isSweeping: Bool { if case .sweeping = status { return true }; return false }

    var blockedReason: String? {
        if case let .blocked(r) = status { return r }
        return nil
    }

    var elapsed: TimeInterval {
        guard let s = startedAt else { return 0 }
        return Date().timeIntervalSince(s)
    }

    mutating func begin() {
        status = .sweeping
        received = 0
        distinct = 0
        startedAt = Date()
    }

    mutating func block(_ reason: String) { status = .blocked(reason) }
    mutating func finish() { status = .finished }

    /// CBManagerState を人間可読な理由に落とす。曖昧な文言にしないこと。
    static func reason(for s: CBManagerState) -> String? {
        switch s {
        case .poweredOn:    return nil
        case .poweredOff:   return "Bluetoothがオフです。設定でオンにしてください。"
        case .unauthorized: return "Bluetoothの使用が許可されていません。設定 → Bluehood で許可してください。"
        case .unsupported:  return "この端末はBluetooth LEに対応していません。"
        case .resetting:    return "Bluetoothを再起動中です。しばらくお待ちください。"
        case .unknown:      return "Bluetoothの状態を確認中です。"
        @unknown default:   return "Bluetoothを利用できません。"
        }
    }
}
