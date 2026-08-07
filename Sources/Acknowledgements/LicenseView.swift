//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import SwiftUI

/// One package's licence, in full, on its own scrolling screen.
///
/// **A view rather than a feature.** It renders a `String` and does nothing — see the note on
/// ``Acknowledgements/State/license`` for why that is where ADR-0013's idiom stops.
internal struct LicenseView: View {
	internal let license: License

	internal var body: some View {
		ScrollView {
			// The licence body, verbatim and unlocalised: it is generated third-party text held
			// as a `String` and rendered from a variable, so extraction skips it and `bundle:`
			// does not belong on it (`CONTEXT.md`, **Not localisable**).
			//
			// `.footnote` because a licence is a wall of pre-wrapped prose and this fits more of
			// it on a phone. It is a text style, so it still scales with Dynamic Type — nothing
			// here clamps, and the text wraps and grows rather than truncating (ADR-0018).
			Text(verbatim: license.text)
				.font(.footnote)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
		}
		// The package's own name, so `verbatim`. Inline, because it is the second level of a
		// push and a large title here would restate what the row you just tapped already said.
		.navigationTitle(Text(verbatim: license.name))
		.navigationBarTitleDisplayMode(.inline)
	}
}
