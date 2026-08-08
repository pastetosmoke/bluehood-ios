// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreLocation
import Foundation

/// スイープを実施した**自分の**位置だけを取る。
///
/// CoreBluetooth 自体に位置情報権限は不要(Androidと異なる)。
/// ここで位置を取るのは、共起判定で「別の場所だったか」を検証するためと、
/// 証拠として自分の行動を記録するため。
///
/// 拒否されてもスイープは動く。ただし空間的な独立性を検証できなくなるので、
/// 共起スコアには上限がかかる(CoPresenceDetector.score の locationKnown 分岐)。
/// 検出した機器の位置は取得も推定も保存もしない。
@MainActor
final class LocationProvider: NSObject, ObservableObject {

    @Published private(set) var current: CLLocation?
    @Published private(set) var authorized = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // 建物単位で十分
        refreshAuthorization()
    }

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        requestIfNeeded()
        guard authorized else { return }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    private func refreshAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: authorized = true
        default: authorized = false
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            refreshAuthorization()
            if authorized { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            // 古い fix を使い回すと全スイープが同じ座標になり、共起判定が空間を検証できなくなる
            guard let l = locations.last, abs(l.timestamp.timeIntervalSinceNow) < 120 else { return }
            current = l
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // 位置が取れないこと自体は致命的ではない。スイープは続行し、
        // 判定側が locationKnown=false として扱う。
    }
}
