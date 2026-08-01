//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Foundation
internal import Testing

@testable internal import Database

extension DatabaseTests {
	/// The generator behind every `id` column's default.
	///
	/// `inMemory()` registers the counting variant, so nothing else in this target ever
	/// reaches the one the app actually ships — and its time-ordering is load-bearing:
	/// `(createdAt, id)` is the app's one sort order, and the `id` tie-break only agrees with
	/// creation order because the ids carry a timestamp.
	@Suite
	struct IDTests {
		@Test
		func uuidV7CarriesTheVersionAndVariantBits() {
			let uuid = uuidV7()

			#expect(uuid.uuid.6 & 0xF0 == 0x70, "version 7")
			#expect(uuid.uuid.8 & 0xC0 == 0x80, "variant 2")
		}

		@Test
		func uuidV7sMintedInDifferentMillisecondsSortInCreationOrder() async throws {
			let first = uuidV7()
			try await Task.sleep(for: .milliseconds(2))
			let second = uuidV7()

			// Within one millisecond the random tail decides, and nothing here claims
			// otherwise: two Lists made in the same instant are two Lists in an arbitrary but
			// identical order on every device, which is all the sort order needs.
			#expect(first.uuidString < second.uuidString)
		}
	}
}
