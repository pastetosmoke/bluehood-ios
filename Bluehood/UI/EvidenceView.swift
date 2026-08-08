// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UniformTypeIdentifiers

/// 証拠パッケージの確認と書き出し。
///
/// 書き出す前に、利用者自身に「これが何を示さないか」を読んでもらう。
/// 中身を理解しないまま提出させると、期待と結果がずれたときの損害が本人に返る。
struct EvidenceView: View {
    let coPresence: CoPresence
    let sweeps: [Sweep]

    @Environment(\.dismiss) private var dismiss
    @State private var package: EvidenceExporter.Package?
    @State private var pdfURL: URL?
    @State private var jsonURL: URL?
    @State private var showRaw = false

    var body: some View {
        NavigationStack {
            List {
                if let pkg = package {
                    summarySection(pkg)
                    caveatSection
                    exportSection
                    rawSection(pkg)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("証拠パッケージ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { cleanup(); dismiss() }
                }
            }
            .task { build() }
        }
    }

    // MARK: - セクション

    private func summarySection(_ pkg: EvidenceExporter.Package) -> some View {
        Section("概要") {
            row("対象", pkg.summary.title)
            if let t = pkg.summary.trackerType { row("種別", t) }
            row("スコア", String(format: "%.1f / 10", pkg.summary.score))
            row("観測", "\(pkg.summary.sweepCount) 回のスイープ")
            row("地点", pkg.summary.locationKnown
                ? "\(pkg.summary.distinctPlaces) 地点" : "位置未記録")
            row("チェーン末端", String(pkg.chainTip.prefix(24)) + "…")
        }
    }

    private var caveatSection: some View {
        Section {
            Label {
                Text("このハッシュチェーンが示すのは記録内部の整合性だけで、内容が真実であることの証明ではありません。このアプリを持つ者は、任意の内容で整合したチェーンを作れます。")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text("第三者機関による時刻認証（RFC 3161）を付けるまで、この記録を「改ざん不可」と説明しないでください。実害がある場合の正しい提出先は警察です。")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("この記録が示さないこと")
        }
    }

    private var exportSection: some View {
        Section("書き出し") {
            if let url = pdfURL {
                ShareLink(item: url) {
                    Label("PDFを共有", systemImage: "doc.richtext")
                }
            }
            if let url = jsonURL {
                ShareLink(item: url) {
                    Label("JSONを共有（検証用）", systemImage: "curlybraces")
                }
            }
            Text("PDFは提出用、JSONは第三者がハッシュチェーンを再計算して検証するためのものです。両方を渡すと検証可能性が上がります。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func rawSection(_ pkg: EvidenceExporter.Package) -> some View {
        Section {
            DisclosureGroup("生のJSONを表示", isExpanded: $showRaw) {
                Text(pkg.json)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    // MARK: - 生成

    private func build() {
        let pkg = EvidenceExporter.export(coPresence, sweeps: sweeps)
        package = pkg

        // 共有のため一時ファイルへ。閉じるときに消す。
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory

        let pdf = dir.appendingPathComponent("bluehood-evidence-\(stamp).pdf")
        if (try? EvidencePDF.render(pkg).write(to: pdf)) != nil { pdfURL = pdf }

        let json = dir.appendingPathComponent("bluehood-evidence-\(stamp).json")
        if (try? Data(pkg.json.utf8).write(to: json)) != nil { jsonURL = json }
    }

    private func cleanup() {
        [pdfURL, jsonURL].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
}
