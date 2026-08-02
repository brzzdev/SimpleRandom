//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models
public import SwiftUI

/// `ListDetail` — one List's Items, its editor sheets and its pinned Randomise (#20).
/// Both tabs push it, which is why it is a target of its own rather than part of the Lists
/// index (ADR-0014).
///
/// **What is here is the seam, not the screen.** #19 wires the Lists index to push this as
/// optional child state (ADR-0013), so the state and the destination have to exist; the
/// Items, the editors and the draw are #20's, and until then the screen says so.
@Feature
public struct ListDetail {
	public struct State: Identifiable {
		public let list: Models.List

		public var id: Models.List.ID { list.id }

		public init(list: Models.List) {
			self.list = list
		}
	}

	public enum Action {}

	public init() {}

	public var body: some Feature {
		EmptyFeature()
	}
}

public struct ListDetailView: View {
	private let store: StoreOf<ListDetail>

	public init(store: StoreOf<ListDetail>) {
		self.store = store
	}

	/// Blank on purpose, the way the three tabs were blank when they were scaffolded.
	///
	/// The obvious placeholder — `ContentUnavailableView("No Items")`, which is the screen's
	/// real empty state — would state something false on every List that has Items, since
	/// nothing here reads them yet. A screen that says nothing is better than one that lies,
	/// and the copy arrives with the Items in #20.
	public var body: some View {
		Color.clear
			.navigationTitle(Text(verbatim: store.list.name))
			.navigationBarTitleDisplayMode(.inline)
	}
}
