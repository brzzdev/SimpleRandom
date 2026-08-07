//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

/// Every package this app pins, one row each, tapping through to the full licence text.
///
/// **No `NavigationStack` of its own.** This screen is pushed from Settings and lives in that
/// tab's stack, exactly as `ListDetailView` lives in the Lists tab's.
public struct AcknowledgementsView: View {
	@Bindable private var store: StoreOf<Acknowledgements>

	public init(store: StoreOf<Acknowledgements>) {
		self.store = store
	}

	public var body: some View {
		List(store.licenses) { license in
			row(license)
		}
		.navigationTitle(Text("Acknowledgements", bundle: #bundle))
		.navigationBarTitleDisplayMode(.inline)
		// The push, off the one optional the state already is. There is no child store to scope
		// because there is no child feature — see the note on ``Acknowledgements/State/license``.
		.navigationDestination(item: $store.license) { license in
			LicenseView(license: license)
		}
	}

	/// Name over version and licence type, and the whole row is the tap target.
	///
	/// The `.plain` style hit-tests the label's drawn content, so without the `contentShape` a
	/// short package name would leave most of the row dead — the same fact `Components`'
	/// `IndexRowButton` exists to hold in one place.
	///
	/// **`IndexRowButton` is not reused, and could not be.** It is an *index* row: it leads with
	/// an emoji column and renders a 🎲 placeholder where a List or a Combo has not been given
	/// one, which is a thing a package has no analogue of and no way to opt out of. `Components`
	/// exists for treatment two tabs would otherwise write twice (`CONTEXT.md`, **Architecture**);
	/// this is a third screen with a different row, so what it shares is the two modifiers rather
	/// than the view.
	private func row(_ license: License) -> some View {
		Button {
			store.send(.rowTapped(license))
		} label: {
			VStack(alignment: .leading, spacing: 2) {
				// The package's own name — data, not a string to look up.
				Text(verbatim: license.name)

				caption(license)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			// Rows wrap and grow tall rather than truncating, which at accessibility text sizes
			// is the difference between a readable credit and half a package name (ADR-0018).
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
			// One element, one label: `1.8.2 · MIT` is read as `version 1.8.2, MIT`, and the `·`
			// is not a thing VoiceOver should be pronouncing.
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(spokenLabel(license))
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}

	/// What sits under the name: the version and the licence type, or the type alone.
	///
	/// One catalogue entry including its separator rather than two fragments joined in Swift —
	/// the translator gets the whole phrase and control over its order, and `·` is not a
	/// punctuation decision made in code (ADR-0022). The version and the type are data, so they
	/// enter as `%@`.
	private func caption(_ license: License) -> Text {
		guard let version = license.version else {
			// A branch pin has no version to state, and there is nothing else to put beside the
			// type — so the row says the one thing it knows rather than the type twice.
			return Text(verbatim: license.type)
		}

		return Text("\(version) · \(license.type)", bundle: #bundle)
	}

	/// The row said as one phrase, with the name in it: the visible row renders the name above
	/// the caption, whereas the spoken label is one sentence and has to carry both (ADR-0022).
	///
	/// **No noun follows the type.** `MIT licence` reads better than `MIT` alone, but `type` is
	/// not always an identifier a noun can follow: TCA26's is the sentence `All rights reserved`,
	/// and `All rights reserved licence` is not English.
	///
	/// **A row with no version says so rather than going quiet**, which is also what makes the
	/// key derivable: a String Catalog cannot name a symbol for a key that is nothing but
	/// placeholders, so `%@, %@` fails the build outright. `unversioned` is the fact the missing
	/// version *is* — the pin is a branch — said in the place the version would have been.
	private func spokenLabel(_ license: License) -> Text {
		guard let version = license.version else {
			return Text("\(license.name), unversioned, \(license.type)", bundle: #bundle)
		}

		return Text("\(license.name), version \(version), \(license.type)", bundle: #bundle)
	}
}
