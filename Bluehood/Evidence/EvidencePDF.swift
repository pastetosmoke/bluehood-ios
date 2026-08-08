// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import UIKit

/// 証拠パッケージのPDF化。
///
/// この文書は警察や弁護士に渡される可能性がある。
/// **過大な主張を載せると、読んだ人が過大評価し、最も助けが必要な場面で梯子が外れる。**
/// だから「この記録が示さないこと」を、示すことと同じ大きさで書く。
/// 見栄えのために制限事項を小さくしたり末尾に追いやったりしない。
enum EvidencePDF {

    private static let pageSize = CGSize(width: 595.2, height: 841.8)   // A4 72dpi
    private static let margin: CGFloat = 48

    static func render(_ pkg: EvidenceExporter.Package) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin

            y = header(&y)
            y = summary(pkg.summary, y: y)
            y = limitations(pkg.summary, y: y)
            y = events(pkg.summary.events, y: y, ctx: ctx)
            _ = integrity(pkg.chainTip, y: y, ctx: ctx)
        }
    }

    // MARK: - セクション

    private static func header(_ y: inout CGFloat) -> CGFloat {
        var y2 = y
        draw("Bluehood Sweep — 共起記録", at: &y2, font: .boldSystemFont(ofSize: 17))
        draw("Co-presence record (self-centered log)", at: &y2, font: .systemFont(ofSize: 10),
             color: .secondaryLabel)
        y2 += 4
        draw("作成日時: \(EvidenceExporter.iso8601(Date()))", at: &y2,
             font: .systemFont(ofSize: 9), color: .secondaryLabel)
        y2 += 10
        line(at: &y2)
        return y2
    }

    private static func summary(_ s: EvidenceExporter.Summary, y: CGFloat) -> CGFloat {
        var y2 = y + 8
        draw("概要", at: &y2, font: .boldSystemFont(ofSize: 13))
        y2 += 2

        row("対象", s.title, at: &y2)
        if let t = s.trackerType { row("種別", t, at: &y2) }
        row("スコア", String(format: "%.1f / 10", s.score), at: &y2)
        row("観測回数", "\(s.sweepCount) 回のスイープ", at: &y2)
        row("地点数", s.locationKnown ? "\(s.distinctPlaces) 地点" : "位置未記録のため不明", at: &y2)
        row("期間", "\(EvidenceExporter.iso8601(s.firstSeen))\n〜 \(EvidenceExporter.iso8601(s.lastSeen))",
            at: &y2)
        y2 += 8
        return y2
    }

    /// 最重要セクション。この記録が「示さないこと」。
    private static func limitations(_ s: EvidenceExporter.Summary, y: CGFloat) -> CGFloat {
        var y2 = y
        line(at: &y2)
        y2 += 8
        draw("この記録について（重要）", at: &y2, font: .boldSystemFont(ofSize: 13))
        y2 += 2

        let items: [String] = [
            "この記録は、作成者自身の位置と、その場で受信したBluetooth電波の特徴のみを含みます。"
                + "検出された機器の所在地は記録していません。機器の所有者も特定していません。",
            "末尾のハッシュ値は記録内部の整合性を示すもので、"
                + "内容が真実であることの証明ではありません。"
                + "このアプリを持つ者は任意の内容で整合したハッシュ列を作成できます。"
                + "第三者機関による時刻認証は行われていません。",
            "スコアは経験則に基づく目安（0〜10）であり、法的な判断ではありません。"
                + "値が高いことは、偶然では説明しにくいという以上の意味を持ちません。",
            "Bluetoothの識別子は定期的に変化するため、同一機器であるという判定は"
                + "電波の特徴に基づく推定です。断定ではありません。",
        ]
        for item in items {
            bullet(item, at: &y2)
        }
        if !s.locationKnown {
            bullet("位置情報が記録されていないため、異なる場所で観測されたことを検証できていません。"
                   + "スコアは低く抑えられていますが、これは安全を意味しません。", at: &y2, warn: true)
        }
        y2 += 8
        return y2
    }

    private static func events(_ events: [EvidenceExporter.Event],
                               y: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        var y2 = y
        line(at: &y2); y2 += 8
        draw("観測記録", at: &y2, font: .boldSystemFont(ofSize: 13))
        y2 += 4

        for (i, e) in events.enumerated() {
            if y2 > pageSize.height - margin - 70 { ctx.beginPage(); y2 = margin }

            draw("\(i + 1). \(EvidenceExporter.iso8601(e.at))", at: &y2,
                 font: .boldSystemFont(ofSize: 10))
            if let l = e.label {
                draw("   場所の記録: \(l)", at: &y2, font: .systemFont(ofSize: 9))
            }
            let pos: String
            if let la = e.lat, let lo = e.lon {
                let acc = e.accuracyM.map { String(format: "±%.0fm", $0) } ?? ""
                pos = String(format: "   自分の位置: %.5f, %.5f %@", la, lo, acc)
            } else {
                pos = "   自分の位置: 記録なし"
            }
            draw(pos, at: &y2, font: .systemFont(ofSize: 9), color: .secondaryLabel)
            draw("   受信強度: \(e.rssi) dBm", at: &y2,
                 font: .systemFont(ofSize: 9), color: .secondaryLabel)
            draw("   hash: \(e.hash.prefix(32))…", at: &y2,
                 font: .monospacedSystemFont(ofSize: 7, weight: .regular), color: .tertiaryLabel)
            y2 += 5
        }
        return y2
    }

    private static func integrity(_ tip: String, y: CGFloat,
                                  ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        var y2 = y
        if y2 > pageSize.height - margin - 90 { ctx.beginPage(); y2 = margin }
        line(at: &y2); y2 += 8
        draw("チェーン末端ハッシュ (SHA-256)", at: &y2, font: .boldSystemFont(ofSize: 11))
        draw(tip, at: &y2, font: .monospacedSystemFont(ofSize: 8, weight: .regular))
        y2 += 4
        draw("各記録は直前の記録のハッシュを含みます。途中の改変は後続すべてのハッシュを変化させます。"
             + "ただしこれは内部の整合性のみを示し、記録の真正性は保証しません。",
             at: &y2, font: .systemFont(ofSize: 8), color: .secondaryLabel)
        return y2
    }

    // MARK: - 描画ヘルパ

    private static func draw(_ text: String, at y: inout CGFloat,
                             font: UIFont, color: UIColor = .label,
                             indent: CGFloat = 0) {
        let w = pageSize.width - margin * 2 - indent
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (text as NSString).draw(
            with: CGRect(x: margin + indent, y: y, width: w, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        y += rect.height + 2
    }

    private static func row(_ k: String, _ v: String, at y: inout CGFloat) {
        let start = y
        draw(k, at: &y, font: .systemFont(ofSize: 10), color: .secondaryLabel)
        y = start
        var vy = start
        drawAt(v, x: margin + 90, y: &vy, font: .systemFont(ofSize: 10))
        y = vy + 2
    }

    private static func drawAt(_ text: String, x: CGFloat, y: inout CGFloat, font: UIFont) {
        let w = pageSize.width - margin - x
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (text as NSString).draw(
            with: CGRect(x: x, y: y, width: w, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        y += rect.height
    }

    private static func bullet(_ text: String, at y: inout CGFloat, warn: Bool = false) {
        var y2 = y
        drawAt("・", x: margin, y: &y2, font: .systemFont(ofSize: 10))
        var ty = y
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: warn ? UIColor.systemOrange : UIColor.label,
        ]
        let w = pageSize.width - margin * 2 - 14
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (text as NSString).draw(
            with: CGRect(x: margin + 14, y: ty, width: w, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        ty += rect.height + 5
        y = ty
    }

    private static func line(at y: inout CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        UIColor.separator.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 1
    }
}
