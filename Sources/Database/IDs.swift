//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Dependencies
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
///
/// Nothing in Foundation, GRDB, SQLiteData or swift-dependencies mints a v7, so this is
/// written out — but only the parts a v4 does not already give: `\.uuid` supplies sixteen
/// random bytes, and the timestamp and the version nibble go over the top of them.
///
/// Both halves come through `@Dependency` rather than `UUID()` and `Date()`, so the one
/// property this function exists for is assertable without a test that waits on the wall
/// clock. `\.date` is already the app's clock seam, and `createdAt` is written through it.
@DatabaseFunction("newID")
nonisolated func uuidV7() -> UUID {
	@Dependency(\.date.now) var now
	@Dependency(\.uuid) var uuid

	var bytes = withUnsafeBytes(of: uuid().uuid) { Array($0) }

	let milliseconds = UInt64((now.timeIntervalSince1970 * 1_000).rounded())
	for offset in 0 ..< 6 {
		bytes[offset] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - UInt64(offset))))
	}
	// Version 7 goes over `UUID()`'s 4. Variant 2 is already what it set, and is written
	// again rather than relied upon: nothing here would notice if that stopped being true.
	bytes[6] = bytes[6] & 0x0F | 0x70
	bytes[8] = bytes[8] & 0x3F | 0x80

	return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
}

/// The generator `inMemory()` registers: `00000000-0000-0000-0000-000000000001` and up, so
/// a test's ids are legible rather than merely unique.
///
/// The counter is process-wide and never resets, which is the point — ids stay distinct
/// across every test in a run, and no test can come to depend on being the first one. It
/// mints through swift-dependencies' own `UUID(_: Int)`, which is what seeds are written
/// with, so a negative seed can never collide with one of these by construction.
@DatabaseFunction("newID")
nonisolated func countingID() -> UUID {
	UUID(countingIDSequence.withLock { count in
		count += 1
		return count
	})
}

private let countingIDSequence = Mutex(0)
