//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

/// One third-party package and the terms it is used under.
///
/// The values are written by `tools/generate-licenses.swift` into `Licenses.generated.swift`;
/// the type lives here so it is linted, documented and reviewable like any other, and so the
/// generated file stays pure data.
///
/// **`version` is optional because a pin need not have one.** TCA26 is pinned to a branch
/// (ADR-0001), and a branch has a revision rather than a version. Rendering the revision instead
/// was rejected: a forty-character sha says nothing to anyone reading a credits screen, and
/// saying nothing is the honest shape of "this is not a released version".
public struct License: Hashable, Identifiable, Sendable {
	/// The package's name as its repository spells it — `GRDB.swift`, `TCA26`, `swift-sharing` —
	/// rather than SwiftPM's lower-cased identity.
	public let name: String

	/// The licence body, verbatim.
	///
	/// **Not localisable, and deliberately so.** It is generated third-party text held as a
	/// `String` and rendered from a variable, so extraction skips it and `bundle:` does not
	/// belong on it. Recorded in `CONTEXT.md` under **Not localisable** so it is not later
	/// "fixed".
	public let text: String

	/// The SPDX identifier where there is one to read as — `MIT`, `Apache-2.0` — and a plain
	/// statement where there is not.
	public let type: String

	/// `nil` for a branch pin. See the note on the type.
	public let version: String?

	public var id: String { name }

	public init(name: String, text: String, type: String, version: String?) {
		self.name = name
		self.text = text
		self.type = type
		self.version = version
	}
}
