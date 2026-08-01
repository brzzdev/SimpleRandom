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
	@StateObject private var store: StoreOf<AppFeature>

	public init() {
		// Prepared before the store is assigned, and written in this order rather than as a
		// property default so the ordering is on the page. A dependency prepared after
		// something has read it is one already read at its default, and `@StateObject`'s
		// autoclosure makes the point easy to lose.
		prepareDependencies { _ in
			// The live database goes here, before any feature can reach for
			// `@Dependency(\.defaultDatabase)`. `Database` ships `appDatabase()` with the
			// schema, so this stays empty until then.
		}
		_store = StateObject(wrappedValue: Store(initialState: AppFeature.State()) { AppFeature() })
	}

	public var body: some Scene {
		WindowGroup {
			AppView(store: store)
		}
	}
}
