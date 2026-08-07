//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2

/// The Acknowledgements screen: every package this app pins, and the licence each is used
/// under.
///
/// This is the credits story's other half. `A brzzdev production` in Settings credits the
/// author; this credits the code, and a solo-authored app has nobody else to name. The app's own
/// licence is not surfaced.
///
/// **It reads nothing and writes nothing.** The list is `Licenses.all`, generated from the full
/// transitive `Package.resolved` graph by `scripts/generate-licences.swift` and committed — the
/// runtime never runs the generator, and there is no database, no dependency and no effect
/// anywhere on this screen.
@Feature
public struct Acknowledgements {
	public struct State {
		/// The licence whose full text is pushed, or `nil` for the list.
		///
		/// **A plain optional value rather than optional child state**, which is the one place in
		/// the app where the far end of a push is not a feature. The detail screen renders a
		/// `String` and does nothing — no actions, no effects, nothing for a reducer to own — so
		/// a `@Feature` there would exist purely to satisfy the shape. ADR-0013 records this as
		/// its one exception, and why it leaves the argument intact.
		public var license: License?

		/// Fixed for the life of the process, so a `let` read once rather than a global the view
		/// reaches for — the same shape as `SettingsFeature`'s `version`.
		internal let licenses = Licenses.all

		public init() {}
	}

	public enum Action {
		case rowTapped(License)
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .rowTapped(let license):
				state.license = license
			}
		}
	}
}
