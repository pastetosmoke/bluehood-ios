// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftData
import SwiftUI

@main
struct BluehoodApp: App {
    var body: some Scene {
        WindowGroup {
            SweepView()
        }
        .modelContainer(for: [Sweep.self, SweepDevice.self])
    }
}
