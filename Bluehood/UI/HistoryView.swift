// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftData
import SwiftUI

/// 過去のスイープと、それらにまたがって現れた機器。
///
/// 1回のスイープは「今ここに何があるか」しか答えない。
/// 別の場所で実行した複数のスイープに同じ機器が出て初めて、
/// 偶然では説明しにくいパターンになる。この画面がその判定を担う。
struct HistoryView: View {
    @Query(sort: \Sweep.startedAt, order: .reverse) private var sweeps: [Sweep]
    @Environment(\.modelContext) private var context

    private var coPresences: [CoPresence] {
        CoPresenceDetector.analyze(sweeps: sweeps)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sweeps.isEmpty {
                    ContentUnavailableView {
                        Label("スイープの記録がありません", systemImage: "clock")
                    } description: {
                        Text("別々の場所で複数回スイープすると、共通して現れる機器を検出できます。")
                    }
                } else {
                    List {
                        coPresenceSection
                        sweepSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("履歴")
        }
    }

    @ViewBuilder
    private var coPresenceSection: some View {
        let items = coPresences
        Section {
            if sweeps.count < 2 {
                Text("判定にはスイープが2回以上必要です。別の場所でもう一度実行してください。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("複数のスイープに共通して現れた機器はありません。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(items) { c in CoPresenceRow(item: c) }
            }
        } header: {
            Text("複数の場所で現れた機器")
        } footer: {
            ScoringNote(hasUnlocated: coPresences.contains { !$0.locationKnown })
        }
    }

    @ViewBuilder
    private var sweepSection: some View {
        Section("スイープ (\(sweeps.count))") {
            ForEach(sweeps) { s in SweepRow(sweep: s) }
                .onDelete { idx in
                    for i in idx { context.delete(sweeps[i]) }
                }
        }
    }
}

private struct CoPresenceRow: View {
    let item: CoPresence

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if item.isConcerning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if item.trackerType != nil {
                    Image(systemName: "tag.fill").font(.caption2).foregroundStyle(.orange)
                }
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Text(String(format: "%.1f", item.score))
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(item.isConcerning ? .orange : .secondary)
            }

            Text(detail).font(.caption).foregroundStyle(.secondary)

            if !item.locationKnown {
                // 位置が無いと「別の場所だった」を検証できない。
                // スコアが低いのは安全だからではなく、判定できていないから。
                Text("位置が記録されていないため、別の場所だったかを検証できていません。スコアは低めに抑えられています。")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        var parts = ["\(item.sweepCount) 回のスイープ"]
        if item.locationKnown { parts.append("\(item.distinctPlaces) 地点") }
        if item.spansDays { parts.append("日をまたぐ") }
        parts.append("最接近 \(item.bestRSSI) dBm")
        return parts.joined(separator: " · ")
    }
}

private struct SweepRow: View {
    let sweep: Sweep

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(sweep.label ?? "無題のスイープ")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if sweep.myLat == nil {
                    Image(systemName: "location.slash")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("\(sweep.startedAt.formatted(date: .abbreviated, time: .shortened)) · "
                 + "\(sweep.devices.count) 機器 · \(Int(sweep.duration)) 秒")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// スコアの意味を明示する。数字だけ出して解釈を利用者に丸投げしない。
private struct ScoringNote: View {
    let hasUnlocated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("スコアは「偶然では説明しにくいか」の目安です。同じ生活圏を共有しているだけの相手を除くため、最初の2地点は加点しません。5以上で注意対象になります。")
            if hasUnlocated {
                Text("位置情報を許可すると、別の場所だったかを検証できるようになり判定の精度が上がります。記録されるのはあなたの位置だけで、検出した機器の位置は記録しません。")
                    .padding(.top, 3)
            }
            Text("スコアが高くても、それ自体は証拠ではありません。実害がある場合は警察に相談してください。")
                .padding(.top, 3)
        }
        .font(.caption2)
    }
}
