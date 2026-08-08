# Bluehood Sweep (iOS)

周囲の Bluetooth LE 広告を受動的に調べ、追跡用タグや不審な機器の有無を確認する iOS アプリ。

**これは手動チェックツールであり、常時監視ではありません。**

---

## Android 版との違い

Android の [Bluehood Scanner](../bluehood-android) は歩いている間ずっと観測し、
複数の独立した場所・時間で繰り返し現れる機器を自動で検知します。
**iOS では同じものが作れません。** これは実装の手抜きではなく、OS の制約です。

| | Android | iOS |
|---|---|---|
| バックグラウンドの無差別スキャン | ✅ | ❌ サービスUUIDの列挙が必須 |
| MACアドレス | ✅ | ❌ アプリ固有UUIDに置換 |
| 製造者固有データ（生バイト列） | ✅ | ✅ |
| 生のADストリーム全体 | ✅ | ❌ パース済み辞書のみ |
| PHY | ✅ | ❌ |
| **Apple Find My / AirTag の検出** | ✅ | ❌ OSがフィルタ |

そのため iOS 版は **「今この場を調べる」前景スイープ**として設計しています。
レンタカー、宿泊先、返却された荷物など、明確に疑っている場面で開いて使うものです。

### AirTag について

iOS は Apple 製 Find My 機器の電波をサードパーティアプリに渡しません。
**このアプリで AirTag は検出できません。** iOS 標準の「持ち物の追跡通知」を有効にしてください。

「検出0件」と「そもそも検出できない」を混同させないため、アプリ内でも常時明示しています。

---

## 仕組み

BLE の MAC は約15分で回転しますが、広告に載る「何者であるか」を示す部分は回転しません。
サービスUUID・会社ID・ベンダー固有の安定部・TX Power を束ねてハッシュし、
MAC が変わっても追える安定キーを作ります。

前景専用でも検知の本質は失われません。Android 版の判定は
「独立した複数の文脈で同一の指紋が再出現するか」を見ますが、
この文脈は連続ログである必要がなく、**スイープ1回を1文脈**と見なせば同じ判定が成立します。
手動になるぶん、文脈の独立性はむしろ明確になります。

詳細は [DESIGN.md](DESIGN.md)。

---

## やらないこと

- **相手の座標を保存しない** — データモデルにその列が存在しません
- **個人を特定しない** — トラッカーは種別のみ判定します
- **能動的な追跡機能を持たない** — 技術的には可能ですが、実装しません
- **通信しない** — 解析はすべて端末内で完結します

証拠出力は「自分がいつ・どこで・この指紋と共起したか」の記録であり、
自力で相手を追うための材料ではありません。被害がある場合は警察に相談してください。

---

## ビルド

`.xcodeproj` は生成物なのでコミットしていません。[XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成します。

```bash
brew install xcodegen
xcodegen generate
open Bluehood-iOS.xcodeproj
```

- iOS 17+
- Xcode 16.4

### CI

| ワークフロー | 契機 | Secrets | 用途 |
|---|---|---|---|
| `ios-build-check` | 毎 push | **不要** | コンパイル検証＋ユニットテスト |
| `ios-unsigned-ipa` | 手動 / タグ | **不要** | 未署名IPA（AltStore用・**課金不要**） |
| `ios-testflight` | タグ `v*` | 必要 | TestFlight へアップロード |
| `ios-ad-hoc` | タグ `v*` | 必要 | Ad Hoc IPA（UDID登録が必要な旧経路） |

### 課金せずに実機で試す（AltStore / SideStore）

Apple Developer Program（$99/年）なしで実機に入れられます。**Mac は不要**で、
AltServer は Windows でも動きます。署名は各自の無料 Apple ID で行うため、
このリポジトリの CI には証明書を一切渡しません。

1. Actions → **iOS Unsigned IPA** → Run workflow
2. 完了後、アーティファクト `Bluehood-unsigned-ipa` をダウンロード
3. [AltStore](https://altstore.io/) の AltServer を PC に入れ、iPhone に AltStore を導入
4. AltStore から `Bluehood-unsigned.ipa` をサイドロード
5. iPhone の 設定 → 一般 → VPNとデバイス管理 で開発者を信頼

制約:

- **7日で失効**します。AltServer が同じ WiFi にいれば自動で更新されます
- 無料 Apple ID でサイドロードできるアプリは**同時に3つまで**（AltStore 自身が1枠を使います）
- AltServer の Windows 版は Apple 公式サイト版の iTunes / iCloud が必要です
  （Microsoft Store 版では動きません）

このアプリは Bluetooth と位置情報しか使わず特殊な entitlement を必要としないため、
無料 Apple ID の署名で動作するはずです。

配布は TestFlight を推奨します。Ad Hoc は 100台/年・UDID の事前登録が要りますが、
TestFlight は外部テスター 10,000 人まで、公開リンクで参加でき、UDID の収集が不要です。
必要としている人に「端末の識別子を教えてください」と要求せずに済むことは、
このアプリの性質上とくに重要です。

TestFlight 用 Secrets:

| 名前 | 中身 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Apple **Distribution** 証明書＋秘密鍵の `.p12` |
| `P12_PASSWORD` | 上記のパスワード |
| `PROVISIONING_PROFILE_BASE64` | **App Store** 用 `.mobileprovision` |
| `PROVISIONING_PROFILE_NAME` | 同プロファイル名 |
| `EXPORT_OPTIONS_APPSTORE_BASE64` | `distribution/ExportOptions.appstore.plist.example` を自分の値に変更したもの |
| `APPLE_TEAM_ID` | Team ID |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64` | App Store Connect API キー |

ビルド番号は `github.run_number` を使うため手動管理は不要です。
TestFlight のビルドは **90日で期限切れ**になるので、継続配布には再アップロードが要ります。

---

## 状態

フェーズ1（前景スイープ）を実装中。実機での動作確認は未実施です。

| フェーズ | 内容 | 状態 |
|---|---|---|
| 1 | 前景スイープ | 実装済み・未検証 |
| 2 | スイープ間の共起判定 | 未着手 |
| 3 | 証拠出力（JSON → PDF → RFC 3161） | 未着手 |
| 4 | Tile/SmartTag の限定的な背景監視 | 未着手 |

「改ざん不可」を名乗るのはフェーズ3で外部タイムスタンプが入ってからです。
アプリ自身が生成したデータにアプリ自身がハッシュチェーンを掛けても、
証明されるのは内部の整合性だけで、真正性ではありません。

---

## ライセンス

[Mozilla Public License 2.0](LICENSE)

MPL 2.0 は**ファイル単位のコピーレフト**です。このリポジトリのファイルを改変した場合、
その改変は公開する義務がありますが、新規ファイルを追加する形での組み込みは
プロプライエタリのままでも構いません。商用利用・App Store 配布とも問題ありません。

指紋アルゴリズムや検知ロジックがクローズドなフォークに取り込まれて改善が還らない、
という事態を防ぎつつ、利用の自由は残す意図です。

なお、**ライセンスは悪用を防ぎません。** 配布条件を定めるものであって、使い方は規定できません。
このツールが監視の道具に転用されないための担保は、ライセンスではなく設計側に置いています
（相手の座標を保存する列を作らない、個体を特定しない、能動追跡機能を実装しない）。
