//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

internal import AppFeature
internal import ComposableArchitecture2
internal import Database
internal import Dependencies
internal import SQLiteData

/// The composition root. `AppHost` makes this the process entry point; everything the app
/// is made of hangs off the one store created here.
public struct SimpleRandomApp: App {
	@StateObject private var store: StoreOf<AppFeature>

	public init() {
		// Prepared before the store is assigned, and written in this order rather than as a
		// property default so the ordering is on the page. A dependency prepared after
		// something has read it is one already read at its default, and `@StateObject`'s
		// autoclosure makes the point easy to lose.
		//
		// `try!` because there is nothing to fall back to: a database that will not open is
		// an app with no data and no way to make any. The sync engine joins it in #29.
		try! prepareDependencies {
			$0.defaultDatabase = try appDatabase()
		}
		_store = StateObject(wrappedValue: Store(initialState: AppFeature.State()) { AppFeature() })
	}

	public var body: some Scene {
		WindowGroup {
			AppView(store: store)
		}
	}
}
