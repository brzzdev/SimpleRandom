//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

/// The Combine index. A placeholder until the index and its one form land — it exists now
/// so `AppFeature` has three real tab peers to scope.
@Feature
public struct CombineFeature {
	public struct State {
		public init() {}
	}

	public init() {}
}

public struct CombineView: View {
	private let store: StoreOf<CombineFeature>

	public init(store: StoreOf<CombineFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Color.clear
				.navigationTitle(Text("Combine", bundle: #bundle))
		}
	}
}
