//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import SwiftUI

/// A List with no Items yet. Its pinned Randomise stays visible and disabled beneath this,
/// with a prompt to add something rather than a button that has quietly gone away.
internal struct ListDetailEmptyState: View {
	internal var body: some View {
		ContentUnavailableView {
			Label { Text("No Items", bundle: #bundle) } icon: { Image(systemName: "text.badge.plus") }
		} description: {
			Text("Add the things you want to pick between.", bundle: #bundle)
		}
	}
}
