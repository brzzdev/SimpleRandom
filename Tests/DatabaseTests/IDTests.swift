//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Dependencies
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
		func uuidV7CarriesItsCreationTimeAndTheVersionBits() {
			let now = Date(timeIntervalSince1970: 1_234_567_890.123)
			let bytes = mintV7(at: now).bytes

			// The first 48 bits are the creation time in milliseconds. That is the whole
			// mechanism: the rest of the value is random, and only this prefix orders.
			#expect(bytes.prefix(6).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
				== UInt64((now.timeIntervalSince1970 * 1_000).rounded()))
			#expect(bytes[6] & 0xF0 == 0x70, "version 7")
			#expect(bytes[8] & 0xC0 == 0x80, "variant 2")
		}

		@Test
		func uuidV7sMintedInDifferentMillisecondsSortInCreationOrder() {
			let earlier = mintV7(at: Date(timeIntervalSince1970: 1_234_567_890))
			let later = mintV7(at: Date(timeIntervalSince1970: 1_234_567_890.002))

			// Within one millisecond the random tail decides instead, and nothing here claims
			// otherwise: two Lists made in the same instant are two Lists in an arbitrary but
			// identical order on every device, which is all the sort order needs.
			#expect(earlier.uuidString < later.uuidString)
		}

		/// One id, minted at a stated instant over a stated generator, so both tests read as
		/// claims about the timestamp rather than about whatever the clock happened to say.
		private func mintV7(at now: Date) -> UUID {
			withDependencies {
				$0.date = .constant(now)
				$0.uuid = .incrementing
			} operation: {
				uuidV7()
			}
		}
	}
}

extension UUID {
	fileprivate var bytes: [UInt8] {
		withUnsafeBytes(of: uuid) { Array($0) }
	}
}
