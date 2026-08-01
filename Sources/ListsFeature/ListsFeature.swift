//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

/// The Lists index. A placeholder until the index lands — it exists now so `AppFeature`
/// has three real tab peers to scope.
@Feature
public struct ListsFeature {
	public struct State {
		public init() {}
	}

	public init() {}
}

public struct ListsView: View {
	private let store: StoreOf<ListsFeature>

	public init(store: StoreOf<ListsFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Color.clear
				.navigationTitle(Text("Lists", bundle: #bundle))
		}
	}
}
