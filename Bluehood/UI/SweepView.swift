// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftData
import SwiftUI

struct SweepView: View {
    @StateObject private var scanner = SweepScanner()
    @Environment(\.modelContext) private var context
    @State private var label = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScopeBanner()
                StatusBar(state: scanner.state, isSweeping: scanner.state.isSweeping) {
                    if scanner.state.isSweeping { finish() } else { scanner.start() }
                }
                content
            }
            .navigationTitle("Bluehood Sweep")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let reason = scanner.state.blockedReason {
            Blocked(reason: reason)
        } else if scanner.hits.isEmpty {
            Idle(isSweeping: scanner.state.isSweeping)
        } else {
            List {
                Section {
                    ForEach(scanner.hits) { hit in DeviceRow(hit: hit) }
                } header: {
                    Text("検出 \(scanner.hits.count) 件 · 近い順")
                } footer: {
                    TrackerCaveat()
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func finish() {
        scanner.stop()
        let sweep = Sweep(label: label.isEmpty ? nil : label)
        sweep.endedAt = Date()
        sweep.receivedCount = scanner.state.received
        for hit in scanner.hits {
            let d = SweepDevice(hit: hit)
            d.sweep = sweep
            sweep.devices.append(d)
        }
        context.insert(sweep)
        saved = true
    }
}

/// このアプリが何であって何でないかを常設で示す。
/// 「常時監視されている」という誤解は、護身ツールでは最も危険な誤解になる。
private struct ScopeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill").font(.caption)
            Text("これは手動チェックです。常時監視ではありません。")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

private struct StatusBar: View {
    let state: ScanState
    let isSweeping: Bool
    let action: () -> Void

    private var dot: Color {
        if state.blockedReason != nil { return .red }
        return isSweeping ? .green : .gray
    }

    private var title: String {
        if state.blockedReason != nil { return "スキャン不可" }
        if isSweeping { return "スイープ中" }
        if case .finished = state.status { return "完了" }
        return "待機中"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                // 受信件数と経過を出す = 生きている証拠を数字で見せる。
                // 「0件」と「動いていない」を利用者が区別できるようにする。
                if isSweeping {
                    Text("受信 \(state.received) 件 · \(Int(state.elapsed)) 秒")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if state.received > 0 {
                    Text("受信 \(state.received) 件").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: action) {
                Text(isSweeping ? "終了" : "スイープ開始")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.blockedReason != nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct DeviceRow: View {
    let hit: SweepHit

    private var badge: Color {
        switch hit.proximity {
        case .veryClose: return .orange
        case .near:      return .yellow
        case .far:       return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if hit.trackerType != nil {
                        Image(systemName: "tag.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(hit.title).font(.body.weight(.medium)).lineLimit(1)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(hit.proximity.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badge)
                Text("\(hit.bestRSSI) dBm")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if hit.name != nil, let v = hit.vendor { parts.append(v) }
        if let t = hit.deviceType { parts.append(t) }
        if hit.isLowEntropy && hit.trackerType == nil { parts.append("匿名化") }
        if parts.isEmpty { parts.append("\(hit.count) 回受信") }
        return parts.joined(separator: " · ")
    }
}

/// AirTagが「検出0件」なのではなく「検出できない」ことを明示する。
/// ここを書かないと、iPhoneユーザーがAirTagは無いと誤解する。
private struct TrackerCaveat: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AirTagはこのアプリでは検出できません", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
            Text("iOSはApple製Find My機器の電波を他社アプリに渡しません。AirTagについてはiOS標準の「持ち物の追跡通知」が担当します。設定で有効にしてください。")
                .font(.caption)
        }
        .padding(.top, 8)
    }
}

private struct Blocked: View {
    let reason: String
    var body: some View {
        ContentUnavailableView {
            Label("スイープできません", systemImage: "exclamationmark.octagon.fill")
        } description: {
            Text(reason)
        }
    }
}

private struct Idle: View {
    let isSweeping: Bool
    var body: some View {
        ContentUnavailableView {
            Label(isSweeping ? "受信待ち" : "スイープ未実行",
                  systemImage: isSweeping ? "dot.radiowaves.left.and.right" : "magnifyingglass")
        } description: {
            Text(isSweeping
                 ? "周囲の電波を受信しています。調べたい場所をゆっくり歩いてください。"
                 : "レンタカー、宿泊先、返却された荷物など、疑わしい場所で実行してください。")
        }
    }
}
