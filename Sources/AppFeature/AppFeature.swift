//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import CombineFeature
public import ComposableArchitecture2
public import ListsFeature
public import SettingsFeature

/// The root feature: three tab peers and the tab the app is showing.
///
/// `currentTab` is plain state bound straight from the view — there is no action for it,
/// and no `BindingReducer` to write. The app always opens on Lists.
@Feature
public struct AppFeature {
	public struct State {
		public var combine = CombineFeature.State()
		public var currentTab: Tab = .lists
		public var lists = ListsFeature.State()
		public var settings = SettingsFeature.State()

		public init() {}
	}

	public enum Action {
		case combine(CombineFeature.Action)
		case lists(ListsFeature.Action)
		case settings(SettingsFeature.Action)
	}

	public enum Tab {
		case combine
		case lists
		case settings
	}

	public init() {}

	public var body: some Feature {
		Features {
			Scope(\.combine, action: \.combine) { CombineFeature() }
			Scope(\.lists, action: \.lists) { ListsFeature() }
			Scope(\.settings, action: \.settings) { SettingsFeature() }
		}
	}
}
