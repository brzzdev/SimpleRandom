//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Models
internal import SwiftUINavigation
internal import UIKit

/// The Settings tab: sections of stock rows, destructive last.
///
/// Three of the six specified rows are not here yet — `Sync` (#29) and `View Logs` (#28) do
/// not exist at all, and `Acknowledgements` is present but disabled until #27 gives it
/// somewhere to push. **There is no `#if DEBUG` section**, and there is not to be one:
/// release and debug builds show the same tab.
public struct SettingsView: View {
	@Bindable private var store: StoreOf<SettingsFeature>

	public init(store: StoreOf<SettingsFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Form {
				appearance
				about
				deleteAllLists
			}
			.navigationTitle(Text("Settings", bundle: #bundle))
		}
	}

	/// The app's one preference, in its own section rather than under `About`, which is for
	/// facts about the app and not for things you set (ADR-0005).
	///
	/// The three cases are written out rather than run off `Theme.allCases`, which is
	/// alphabetical — Dark, Light, System — and would put the picker in an order nobody
	/// reading the spec asked for.
	private var appearance: some View {
		Section {
			Picker(selection: $store.theme) {
				Text("Light", bundle: #bundle).tag(Theme.light)
				Text("Dark", bundle: #bundle).tag(Theme.dark)
				Text("System", bundle: #bundle).tag(Theme.system)
			} label: {
				Text("Theme", bundle: #bundle)
			}
		} header: {
			Text("Appearance", bundle: #bundle)
		}
	}

	/// One row of two lines, then the push. `A brzzdev production` is the whole credits half
	/// of "licences and credits" — the Acknowledgements screen credits the code, and a
	/// solo-authored app has nobody else to name.
	private var about: some View {
		Section {
			Button {
				// Written from here rather than routed through an action, on the argument
				// CONTEXT.md makes for the re-roll announcement: this is a UI-layer effect on
				// nothing the feature owns, `SettingsFeature` carries no test target
				// (ADR-0019), and a seam in front of it would only ever test its own mock. It
				// is also what keeps UIKit out of the feature.
				UIPasteboard.general.string = store.version.formatted
			} label: {
				VStack(alignment: .leading, spacing: 4) {
					Text("Version \(store.version.marketing) (\(store.version.build))", bundle: #bundle)
					Text("A brzzdev production", bundle: #bundle)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
			// Otherwise a `Button` in a `Form` renders its whole label in the accent colour,
			// which would make a row you can copy look like a row that does something.
			.buttonStyle(.plain)

			// Disabled until #27, which builds both screens behind it. The row is here so the
			// section is the shape it ships as; what it is missing is a destination, and a
			// dimmed row says that where a link to a blank screen would not.
			NavigationLink {
				EmptyView()
			} label: {
				Text("Acknowledgements", bundle: #bundle)
			}
			.disabled(true)
		} header: {
			Text("About", bundle: #bundle)
		}
	}

	/// Alone in an unheadered trailing section, because it is not one of a set of things you
	/// might do — it is the thing you do once and cannot undo.
	///
	/// Disabled when there is nothing for it to take. `CONTEXT.md` says "no Lists", which was
	/// written when Combos were outside the gesture; now that they are inside it, a Combo
	/// outliving every List it was made from is a real state, and a button that refused to
	/// clear it would be dimmed with something still to delete.
	private var deleteAllLists: some View {
		Section {
			Button(role: .destructive) {
				store.send(.deleteAllListsButtonTapped)
			} label: {
				Text("Delete All Lists", bundle: #bundle)
			}
			.disabled(store.comboIDs.isEmpty && store.listIDs.isEmpty)
		}
		// The dialog states the real counts and the real blast radius. The specificity is
		// the safety mechanism: a typed `DELETE` confirmation was rejected as a keyboard on
		// a screen that otherwise needs none.
		//
		// A confirmation dialog rather than the alert both indexes raise, and the anchoring
		// that argued against one there argues for one here. It hangs on the destructive
		// section rather than on the `Form`, because a dialog points at whatever it is
		// attached to: from the `Form` it points at `About`, naming a row it has nothing to
		// do with.
		//
		// `item:` is SwiftUINavigation's — it takes the one optional the child state already
		// is and derives the presentation flag from it internally, so there is no second
		// `Binding<Bool>` to keep in step.
		.confirmationDialog(
			item: $store.scope(\.confirmDeleteAll, action: \.confirmDeleteAll),
			titleVisibility: .visible,
		) { deletion in
			// Inflected here rather than left to the `Text`, because a dialog title is not
			// rendered by SwiftUI — it is extracted as a plain string for
			// `UIAlertController`, and that extraction runs no morphology pass, so a `Text`
			// holding the key renders the literal `^[7 lists](inflect: true)`.
			// `AttributedString(localized:bundle:)` runs the pass itself, and CONTEXT.md's
			// enumerated call sites carry it.
			Text(
				AttributedString(
					localized: "Delete all ^[\(deletion.listCount) lists](inflect: true), ^[\(deletion.itemCount) items](inflect: true) and ^[\(deletion.comboCount) combos](inflect: true)?",
					bundle: #bundle,
				)
			)
		} actions: { _ in
			Button(role: .destructive) {
				store.send(.confirmDeleteAll(.deleteButtonTapped))
			} label: {
				Text("Delete All Lists", bundle: #bundle)
			}
			// No Cancel is written here: unlike an alert, a confirmation dialog supplies its
			// own however full the actions builder is.
		} message: { _ in
			Text(
				"This removes them from this iPhone and from iCloud on all your devices. It cannot be undone.",
				bundle: #bundle,
			)
		}
	}
}
