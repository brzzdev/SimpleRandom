//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import CombineFeature
internal import ListsFeature
internal import SettingsFeature

public struct AppView: View {
	@Bindable private var store: StoreOf<AppFeature>

	public init(store: StoreOf<AppFeature>) {
		self.store = store
	}

	public var body: some View {
		TabView(selection: $store.currentTab) {
			// The label is spelled out rather than `Tab("Lists", systemImage:)` because that
			// initialiser takes no `bundle:`, and every string here lives in this target's
			// own catalogue.
			Tab(value: .lists) {
				ListsView(store: store.scope(\.lists, action: \.lists))
			} label: {
				Label { Text("Lists", bundle: #bundle) } icon: { Image(systemName: "list.bullet") }
			}
			Tab(value: .combine) {
				CombineView(store: store.scope(\.combine, action: \.combine))
			} label: {
				Label { Text("Combine", bundle: #bundle) } icon: { Image(systemName: "rectangle.stack") }
			}
			Tab(value: .settings) {
				SettingsView(store: store.scope(\.settings, action: \.settings))
			} label: {
				Label { Text("Settings", bundle: #bundle) } icon: { Image(systemName: "gearshape") }
			}
		}
	}
}
