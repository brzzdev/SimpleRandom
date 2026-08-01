//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

/// The Settings form. A placeholder until the six rows land — it exists now so
/// `AppFeature` has three real tab peers to scope.
@Feature
public struct SettingsFeature {
	public struct State {
		public init() {}
	}

	public init() {}
}

public struct SettingsView: View {
	private let store: StoreOf<SettingsFeature>

	public init(store: StoreOf<SettingsFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Color.clear
				.navigationTitle(Text("Settings", bundle: #bundle))
		}
	}
}
