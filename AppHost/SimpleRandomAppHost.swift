//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import App
internal import SwiftUI

// The whole of the app shell. `SimpleRandomApp` lives in the package's `App` target so the
// composition root sits with the modules it wires together; this file exists only because
// a `.app` needs its entry point in the Xcode target.
@main
enum SimpleRandomAppHost {
	static func main() {
		SimpleRandomApp.main()
	}
}
