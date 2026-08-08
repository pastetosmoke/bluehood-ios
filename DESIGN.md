# Bluehood Sweep (iOS) — 設計

Android版 Bluehood Scanner の iOS 対応。**移植ではなく別スコープの製品**として設計する。

---

## 1. これは何で、何ではないか

**これは**: 「今この場に何があるか」を能動的に調べる手動スイープツール。
レンタカー、ホテルの部屋、返却された鞄、別れた相手が触れた持ち物 — 明確に疑っている場面で開いて使う。

**これではない**: 常時監視。iOS はバックグラウンドの無差別 BLE スキャンを許可しないため、
Android 版のような「歩いていれば勝手に尾行を検知する」動作は**原理的に作れない**。

この線引きを製品名・UI・ページのすべてで貫く。同じ名前・同じ説明で出すと、
「守られている」と誤認した利用者が生まれる。それがこのプロジェクトで一貫して潰してきた失敗モードであり、
護身ツールにおける最悪の欠陥である。

### 名前を分ける
- Android: **Bluehood Scanner**（継続監視）
- iOS: **Bluehood Sweep**（手動チェック）

---

## 2. iOS で取れるもの・取れないもの

`CBCentralManager` の `didDiscover` で渡される `advertisementData` から取得可能:

| 要素 | キー | 可否 |
|---|---|---|
| サービスUUID | `CBAdvertisementDataServiceUUIDsKey` | ✅ |
| 製造者固有データ（**生バイト列**） | `CBAdvertisementDataManufacturerDataKey` | ✅ |
| サービスデータ | `CBAdvertisementDataServiceDataKey` | ✅ |
| TX Power | `CBAdvertisementDataTxPowerLevelKey` | ✅ |
| ローカル名 | `CBAdvertisementDataLocalNameKey` | ✅ |
| RSSI | `didDiscover` の引数 | ✅ |
| 広告間隔 | `allowDuplicates` の連続コールバックから推定 | △ 前景のみ |
| MACアドレス | — | ❌ アプリ固有UUIDに置換 |
| 生のADストリーム全体 | — | ❌ パース済み辞書のみ |
| PHY | — | ❌ |

**重要**: 製造者固有データは生のバイト列で取れる。
Android版 `BleFingerprint` が使う要素の大半はそのまま移植できる。

### 越えられない壁は2つ
1. **バックグラウンドの無差別スキャン不可**。`scanForPeripherals(withServices: nil)` は
   バックグラウンドで何も返さない。サービスUUIDの列挙が必須。
2. **Apple製 Find My 広告がフィルタされる**。AirTag は製造者データ `0x004C` で広告し
   サービスUUIDを持たないため、背景スキャンの対象にできず、かつ iOS がサードパーティに渡さない。
   → **AirTag検知は iOS 標準機能に委ねる**。アプリ内でその旨を明示し、設定への導線を置く。

---

## 3. 核となる設計判断: スイープ間の共起

前景専用でも尾行検知の本質は失われない。

Android版の `StalkerDetector` は「独立した複数の文脈で同一指紋が再出現するか」を見る。
この「文脈」は**連続ログである必要がない**。自宅でスイープし、職場でスイープし、
両方に同じ指紋が出たなら、それは同じ共起シグナルである。

つまり **スイープ1回 = 1つの文脈** と見なせば、既存の判定ロジックがそのまま活きる。
自動ではなく手動になるが、判定の質は落ちない。むしろ利用者が意図して別の場所で
実行するため、文脈の独立性は連続ログより明確になる。

```
Android: 連続ログ → 自動で文脈分割 → 共起判定
iOS:     手動スイープ×N → 1スイープ=1文脈 → 同じ共起判定
```

`StalkerDetector.score()` の入力は「観測列」と「文脈列」なので、
文脈の作り方を差し替えるだけでロジックは共有できる。移植コストが低い。

---

## 4. アーキテクチャ

```
SweepScanner (CoreBluetooth)
    ↓ Advertisement
Fingerprint  ──→ stableKey
    ↓
SweepStore (SwiftData)
    Sweep ──< Observation
    ↓
CoPresenceDetector  (Android の StalkerDetector 相当)
TrackerClassifier   (Android から移植)
DeviceNamer         (Android から移植)
    ↓
SwiftUI View + ScanState
```

- **UI**: SwiftUI
- **永続化**: SwiftData（iOS 17+）
- **最低対応**: iOS 17

---

## 5. スキャナ実装の骨子

```swift
import CoreBluetooth

@MainActor
final class SweepScanner: NSObject, ObservableObject {

    @Published private(set) var state = ScanState()
    private var central: CBCentralManager!
    private var hits: [String: SweepHit] = [:]   // stableKey -> 集約

    override init() {
        super.init()
        // showPowerAlert=false: 電源OFFを我々のUIで正直に説明する。
        // システムのアラートに任せると、閉じられた後に「動いているつもり」の状態が残る。
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func startSweep() {
        guard central.state == .poweredOn else {
            state.blocked(reason: Self.reason(for: central.state)); return
        }
        hits.removeAll()
        // allowDuplicates: true は前景でのみ有効。
        // RSSI推移と広告間隔の推定に必須なので、スイープは前景専用と割り切る。
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state.sweeping()
    }

    func stopSweep() {
        central.stopScan()
        state.stopped()
    }

    private static func reason(for s: CBManagerState) -> String {
        switch s {
        case .poweredOff:   return "Bluetoothがオフです"
        case .unauthorized: return "Bluetoothの使用が許可されていません"
        case .unsupported:  return "この端末はBLEに対応していません"
        case .resetting:    return "Bluetoothを再起動中です"
        default:            return "Bluetoothを準備中です"
        }
    }
}

extension SweepScanner: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            // 状態変化で自動的にUIへ反映。スキャン中に電源を切られても黙らない。
            if central.state != .poweredOn { self.state.blocked(reason: Self.reason(for: central.state)) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let adv = Advertisement(
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs:     advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [],
            serviceData:      advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:],
            txPower:          (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            localName:        advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi:             RSSI.intValue,
            at:               Date()
        )
        Task { @MainActor in self.ingest(adv) }
    }
}
```

---

## 6. 指紋の移植

Android の `BleFingerprint` と**同じ形**だが、PHY が無いぶん入力が異なる。
値が一致しないので、**キーにバージョンを埋めて混同を防ぐ**。

```swift
struct Fingerprint {
    /// v2-ios: PHY を含まない。Android の v1 キーとは比較できない(意図的)。
    static func stableKey(_ adv: Advertisement) -> String {
        var parts: [String] = ["v2-ios"]
        parts.append(adv.serviceUUIDs.map(\.uuidString).sorted().joined(separator: ","))
        if let m = adv.manufacturerData, m.count >= 2 {
            let cid = UInt16(m[0]) | (UInt16(m[1]) << 8)     // 会社IDはリトルエンディアン
            parts.append(String(format: "%04X", cid))
            parts.append(stablePrefix(companyID: cid, data: m).hexString)
        }
        parts.append(adv.serviceData.keys.map(\.uuidString).sorted().joined(separator: ","))
        parts.append(adv.txPower.map(String.init) ?? "-")
        return sha256(parts.joined(separator: "|"))
    }

    /// ベンダーごとに「回転しない先頭部分」の長さが違う。Android版と同じ値を使う。
    private static func stablePrefix(companyID: UInt16, data: Data) -> Data {
        let n: Int
        switch companyID {
        case 0x004C: n = 2      // Apple
        case 0x0006: n = 1      // Microsoft
        case 0x00E0: n = 0      // Google
        default:     n = 6
        }
        let body = data.dropFirst(2)                 // 会社IDを除いた本体
        return Data(body.prefix(n))
    }
}
```

`isLowEntropy`（サービスUUID・製造者データ・サービスデータがすべて空）の判定も同じ。

---

## 7. トラッカー検知

Android の `TrackerClassifier` から移植するが、**iOS では拾えるものが減る**。

| 種別 | 署名 | 前景 | 背景 |
|---|---|---|---|
| Tile | UUID `0xFEED` | ✅ | ✅ UUID列挙で可 |
| Samsung SmartTag | UUID `0xFD5A` / 製造者 `0x0075` | ✅ | ✅ UUIDのみ |
| Google FMD | UUID `0xFEAA` | ✅ | ✅ |
| **Apple Find My / AirTag** | 製造者 `0x004C` 先頭 `0x12` | ❌ フィルタ | ❌ |

AirTag が拾えないことは**UI上で明示する**。「検出なし」と「そもそも検出できない」を
同じ画面表現にしてはいけない。トラッカー一覧に常設の注記を置き、
iOS 標準の追跡通知を有効にする導線を併記する。

---

## 8. 正直な状態表示

Android の `ScanState` と同じ思想を適用する。iOS 固有の追加事項:

- `CBManagerState` を購読し、`poweredOff` / `unauthorized` を**理由付きで**表示
- `CBCentralManagerOptionShowPowerAlertKey: false` にして、
  電源OFFの説明を自前UIで行う（システムアラートは一度閉じると消え、後に何も残らない）
- スイープ中は経過秒数と受信件数を常時表示 — 「動いている証拠」を数字で見せる
- **画面上部に常設で「これは手動チェックです。常時監視ではありません」**

---

## 9. データモデル

```swift
@Model final class Sweep {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var label: String?          // 「レンタカー」「ホテル301」など利用者が付ける
    var myLat: Double?          // 自分の座標のみ。相手の座標は持たない(Android版と同じ線引き)
    var myLon: Double?
    var myAccuracyM: Double?
    @Relationship(deleteRule: .cascade) var observations: [SweepObservation]
}

@Model final class SweepObservation {
    var stableKey: String
    var firstSeen: Date
    var lastSeen: Date
    var bestRSSI: Int           // スイープ中の最大値 = 最接近時
    var count: Int
    var name: String?
    var vendor: String?
    var deviceType: String?
    var trackerType: String?
    var isLowEntropy: Bool
    var rawManufacturerHex: String?
}
```

`Observation` に相手座標のフィールドを作らないという構造上の防御線は iOS 版でも維持する。

---

## 10. Info.plist / 権限

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>周囲のBluetooth機器を調べ、追跡用タグの有無を確認するために使用します。</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>証拠記録として、スイープを実施した自分の位置のみを記録します。相手の位置は記録しません。</string>
```

- CoreBluetooth 自体に位置情報権限は**不要**（Android と異なる）
- 位置情報は証拠記録のためだけに使う。拒否されてもスイープは動く
- フェーズ2で背景監視を入れる場合のみ `UIBackgroundModes: [bluetooth-central]` を追加

---

## 11. フェーズ計画

**フェーズ1 — 前景スイープ（最小で価値が出る）**
1. `SweepScanner` + `ScanState`
2. `Fingerprint` / `DeviceNamer` / `TrackerClassifier` の移植
3. スイープ実行画面（経過・件数・結果一覧、RSSI で近い順）
4. SwiftData 永続化

**フェーズ2 — スイープ間の共起判定**
5. `CoPresenceDetector`（`StalkerDetector` の文脈生成だけ差し替え）
6. 「このスイープと過去のスイープに共通する機器」表示

**フェーズ3 — 証拠**
7. JSON + ハッシュチェーン出力（Android と同一フォーマット）
8. PDF 整形
9. RFC 3161 タイムスタンプ（外部アンカー。これが無い限り「改ざん不可」とは名乗らない）

**フェーズ4 — 背景監視（限定）**
10. サービスUUID列挙による Tile / SmartTag 常時監視 + ローカル通知
11. レート制限の実測と、UI での正直な表現

---

## 12. 実装前に一次情報で確認すべきこと

以下は**未確認**。実装判断の前に Apple 公式ドキュメントで裏を取ること。

- [ ] バックグラウンドの UUID 指定スキャンで、実際にどの程度の頻度でコールバックが来るか（レート制限の実測）
- [ ] `CBCentralManager` の State Preservation and Restoration がアプリ終了後の復帰で機能する条件
- [ ] Apple が Find My 広告をフィルタする挙動の正確な範囲（製造者データ全体か、特定の型のみか）
- [ ] DULT 準拠トラッカーの現行広告仕様（署名が変わっていないか）
- [ ] App Store 審査における BLE スキャン系アプリの扱い（前景スイープなら通しやすいはず、という想定の検証）

---

## 13. 既存 CI との関係

`bluehood-ios-github-actions.zip` の GitHub Actions はそのまま使える。
`Bluehood-iOS.xcodeproj` を置けば動く。ただし2点:

- `security import` の後に `security set-key-partition-list` を追加すること。
  無いと `codesign` が keychain アクセスのプロンプト待ちで CI がハングする既知の失敗がある。
- Ad Hoc は**年間100台・UDID事前登録**。実際に必要な人へ届けるには最終的に App Store 審査が要る。
