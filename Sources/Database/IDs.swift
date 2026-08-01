//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Foundation
internal import SQLiteData
internal import Synchronization

// Both generators below register under the SQL name `newID`, which is what every table's
// `id` column defaults to. No insert site anywhere in the app mentions an id, so none can
// forget one.
//
// The name is deliberately **not** `uuid()`. That function exists in Apple's SQLite build,
// so shadowing it would mean a forgotten registration silently falls through to a v4
// generator instead of failing; under a bespoke name the same mistake is a loud
// `no such function: newID`.

/// The generator `appDatabase()` registers: a UUIDv7, whose 48-bit millisecond prefix makes
/// ids sort in creation order.
///
/// That is what makes `(createdAt, id)` — the app's one sort order — agree with insertion
/// order rather than breaking ties arbitrarily. It does not fix clock skew between devices,
/// and nothing short of a logical clock would.
@DatabaseFunction("newID")
nonisolated func uuidV7() -> UUID {
	var bytes = [UInt8](repeating: 0, count: 16)
	for index in bytes.indices {
		bytes[index] = .random(in: .min ... .max)
	}

	let milliseconds = UInt64((Date().timeIntervalSince1970 * 1_000).rounded())
	for offset in 0 ..< 6 {
		bytes[offset] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - UInt64(offset))))
	}
	bytes[6] = bytes[6] & 0x0F | 0x70 // Version 7.
	bytes[8] = bytes[8] & 0x3F | 0x80 // Variant 2.

	return bytes.uuid
}

/// The generator `inMemory()` registers: `00000000-0000-0000-0000-000000000001` and up, so
/// a test's ids are legible rather than merely unique.
///
/// The counter is process-wide and never resets, which is the point — ids stay distinct
/// across every test in a run, and no test can come to depend on being the first one. The
/// shape matches swift-dependencies' `UUID(_: Int)`, so seeds written with negative ids can
/// never collide with these.
@DatabaseFunction("newID")
nonisolated func countingID() -> UUID {
	let count = countingIDSequence.withLock { count in
		count += 1
		return count
	}

	var bytes = [UInt8](repeating: 0, count: 16)
	withUnsafeBytes(of: UInt64(count).bigEndian) { bytes.replaceSubrange(8 ..< 16, with: $0) }
	return bytes.uuid
}

private let countingIDSequence = Mutex(0)

extension [UInt8] {
	/// The sixteen bytes read back as a `UUID`, whatever produced them.
	fileprivate var uuid: UUID {
		withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
	}
}
