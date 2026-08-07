//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Acknowledgements
internal import Models
internal import SwiftUINavigation
internal import UIKit

/// The Settings tab: sections of stock rows, destructive last.
///
/// Two of the six specified rows are not here yet — `Sync` (#29) and `View Logs` (#28) do not
/// exist at all. **There is no `#if DEBUG` section**, and there is not to be one: release and
/// debug builds show the same tab.
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
			// The tab's one push, and the same `.navigationDestination(item:)` the other two
			// tabs push their details with — no `[Path.State]` stack is introduced (ADR-0013).
			.navigationDestination(
				item: $store.scope(\.acknowledgements, action: \.acknowledgements),
				destination: AcknowledgementsView.init,
			)
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

			// A `Button` rather than a `NavigationLink`, because the push is driven by state the
			// feature owns rather than by the link's own destination (ADR-0013).
			//
			// That costs the two things a `NavigationLink` draws for free, and both are put back
			// by hand: `.plain` so the row is not rendered in the accent colour, which would make
			// a row that pushes look like a row that acts — the same reason the `Version` row
			// above sets it — and a chevron, because a `Form` row that pushes has one everywhere
			// else in iOS and its absence is what tells you a row is inert.
			//
			// Hidden from VoiceOver: the row is already announced as a button, and "chevron
			// forward" after the name says nothing.
			Button {
				store.send(.acknowledgementsButtonTapped)
			} label: {
				HStack {
					Text("Acknowledgements", bundle: #bundle)
					Spacer()
					Image(systemName: "chevron.forward")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(.tertiary)
						.accessibilityHidden(true)
				}
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
		} header: {
			Text("About", bundle: #bundle)
		}
	}

	/// What the delete-everything dialog asks, in the five shapes it can take.
	///
	/// **A clause is dropped rather than counted at zero.** All three counted unconditionally
	/// reads `Delete all 3 lists, 10 items and 0 combos?` to everyone who has never opened the
	/// Combine tab, and `Delete all 0 lists, 0 items and 2 combos?` to anyone whose Combos
	/// outlived their Lists. `inflect: true` agrees the noun with its number; it does not
	/// suppress a zero. Awkward copy is bad anywhere and worse here, where the counts *are*
	/// the safety mechanism.
	///
	/// **Five whole phrases rather than clauses joined in Swift**, which is ADR-0022's rule and
	/// the reason this is a `switch` and not a `[String].joined(separator:)`. A join hands the
	/// translator fragments with no control over word order, and picks the separator and the
	/// "and" in code by someone thinking in English. Items imply Lists, so of the eight
	/// combinations only these five exist, and the all-zero one cannot arise — the row that
	/// raises this is disabled there.
	///
	/// Inflected here rather than left to the `Text`, because a dialog title is not rendered by
	/// SwiftUI — it is extracted as a plain string for `UIAlertController`, and that extraction
	/// runs no morphology pass, so a `Text` holding the key renders the literal
	/// `^[7 lists](inflect: true)`. `AttributedString(localized:bundle:)` runs the pass itself,
	/// and CONTEXT.md's enumerated call sites carry it.
	private func title(listCount: Int, itemCount: Int, comboCount: Int) -> Text {
		guard listCount > 0 else {
			// Only Combos left to take, which is a Combo outliving every List it was built from.
			return Text(
				AttributedString(
					localized: "Delete all ^[\(comboCount) combos](inflect: true)?",
					bundle: #bundle,
				)
			)
		}

		return switch (itemCount > 0, comboCount > 0) {
		case (true, true):
			Text(
				AttributedString(
					localized: "Delete all ^[\(listCount) lists](inflect: true), ^[\(itemCount) items](inflect: true) and ^[\(comboCount) combos](inflect: true)?",
					bundle: #bundle,
				)
			)

		case (true, false):
			Text(
				AttributedString(
					localized: "Delete all ^[\(listCount) lists](inflect: true) and ^[\(itemCount) items](inflect: true)?",
					bundle: #bundle,
				)
			)

		case (false, true):
			Text(
				AttributedString(
					localized: "Delete all ^[\(listCount) lists](inflect: true) and ^[\(comboCount) combos](inflect: true)?",
					bundle: #bundle,
				)
			)

		case (false, false):
			Text(
				AttributedString(
					localized: "Delete all ^[\(listCount) lists](inflect: true)?",
					bundle: #bundle,
				)
			)
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
			title(listCount: deletion.listCount, itemCount: deletion.itemCount, comboCount: deletion.comboCount)
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
