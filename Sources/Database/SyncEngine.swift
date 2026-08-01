//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SQLiteData

internal import Models

/// The sync engine over one person's own iPhones, and the one place the six tables are
/// opted into sync.
///
/// **`ListDraw` is a private table from day one.** Private tables still sync across one
/// person's devices, so this changes nothing in v1 — but a shared List would not carry one
/// participant's draws into another's deck. Deck state is written on every tap, so
/// relocating it after ship would be a live data migration under a shared schema rather
/// than the dead column a never-written reserved column leaves behind. That is why it had
/// to be decided before the first build or not at all (ADR-0006).
///
/// Nothing calls this yet: the CloudKit container, the entitlements and the
/// `SyncEngineDelegate` that keeps local data on sign-out land with #29. It is declared
/// here because the schema it validates is this ticket's, and because the constraints it
/// enforces at runtime are the ones `DatabaseTests` asserts.
public func syncEngine(for database: any DatabaseWriter) throws -> SyncEngine {
	try SyncEngine(
		for: database,
		tables: Combo.self, ComboDraw.self, ComboList.self, Item.self, Models.List.self,
		privateTables: ListDraw.self,
	)
}
