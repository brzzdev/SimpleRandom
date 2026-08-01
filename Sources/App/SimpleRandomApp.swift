//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

internal import AppFeature
internal import ComposableArchitecture2
internal import Dependencies

/// The composition root. `AppHost` makes this the process entry point; everything the app
/// is made of hangs off the one store created here.
public struct SimpleRandomApp: App {
	@StateObject private var store = Store(initialState: AppFeature.State()) { AppFeature() }

	public init() {
		prepareDependencies { _ in
			// The live database is prepared here, before any feature can reach for
			// `@Dependency(\.defaultDatabase)`. `Database` ships `appDatabase()` with the
			// schema, so this stays empty until then — the call site is what matters now,
			// because a dependency prepared late is one already read at its default.
		}
	}

	public var body: some Scene {
		WindowGroup {
			AppView(store: store)
		}
	}
}
