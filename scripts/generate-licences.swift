//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

// Regenerates `Sources/Acknowledgements/Licenses.generated.swift` from `Package.resolved` and
// the checkouts SwiftPM has already made under `.build/checkouts`. Run it with `just licences`;
// the app never runs it, and the output is committed. `.github/workflows/licences.yml` runs it
// weekly and opens a PR, so the screen catches up without anyone having to remember.
//
// **The whole transitive graph is credited, test-only dependencies included.** `Package.resolved`
// is the list of everything this repo pins, and a licence that only applies to code shipped in
// the binary is a distinction this screen cannot make and nobody reading it wants.
//
// **It fails rather than guesses**, and every guess it could make is a failure instead: a missing
// checkout, no licence file and no stated terms, terms it cannot classify, terms it can classify
// two ways, a package that has both a file and a stated entry, or a body carrying a sequence the
// generated literal cannot hold verbatim. Shipping a package as `Unknown` — or worse, quietly
// dropping it, or crediting one licence for another — is the failure this screen exists to
// prevent, and it would be invisible in a diff of an already-long generated file.

// MARK: - Package.resolved

/// One pin, as `Package.resolved` version 3 writes it.
struct Pin: Decodable {
	struct State: Decodable {
		let version: String?
	}

	let location: String
	let state: State
}

struct Resolved: Decodable {
	let pins: [Pin]
}

// MARK: - Licence discovery

/// The packages that ship no licence file at all, and what to credit them with instead.
///
/// This exists for TCA26 and is deliberately not a fallback: an entry here is a human reading a
/// repository and writing down what it says, and anything not listed stops the run.
///
/// TCA26's README ends `© 2026 Point-Free, Inc. All rights reserved.` and the repository carries
/// no `LICENSE`. That is the honest thing to display — it is an unreleased branch pinned for its
/// `StoreActor` (ADR-0001), not open-source code with terms that were mislaid.
///
/// **The text is the notice and nothing else.** Prose explaining the situation would be our
/// English rather than the package's, and it would ship past the string catalogues — the
/// `Not localisable` exemption in `CONTEXT.md` covers generated third-party text, not commentary
/// smuggled in beside it.
let statedTerms: [String: (type: String, text: String)] = [
	"TCA26": (type: "All rights reserved", text: "© 2026 Point-Free, Inc. All rights reserved."),
]

/// Every licence this script recognises in a body, read as SPDX where there is an identifier to
/// read as — that is the name people searching for a package's terms already know.
///
/// Matched on the text rather than on the file name: the file is called `LICENSE`, `LICENCE` or
/// `LICENSE.txt` depending on the author, and none of those spellings says what is in it.
///
/// **Every recogniser is run, and the caller demands exactly one hit.** Returning at the first
/// match would read a dual-licensed body — a file offering Apache-2.0 *or* MIT is an ordinary
/// thing to ship — as whichever recogniser happened to be written first, and credit terms the
/// package never picked. Two hits is not a licence this script knows; it is a licence this script
/// cannot choose between, and that is the caller's to refuse.
///
/// **Recognising is not the same as verifying.** These are the hallmarks of each licence, not a
/// diff against its canonical text, so a body that carries them *and something else* is
/// recognised by its hallmarks. The MIT case below says what that costs.
func licenceTypes(in text: String) -> [String] {
	var types: [String] = []

	if text.contains("Apache License"), text.contains("Version 2.0") {
		// Both Apache-licensed pins here are Swift-project repositories, which append the
		// exception rather than shipping stock Apache-2.0. Naming it matters: the exception is
		// the clause that makes linking the runtime into a closed binary unremarkable.
		types.append(
			text.range(of: "Runtime Library Exception", options: .caseInsensitive) != nil
				? "Apache-2.0 with Runtime Library Exception"
				: "Apache-2.0"
		)
	}

	// Three hallmarks rather than the grant sentence alone. GRDB.swift's licence opens on its
	// copyright line rather than on a title, so a title cannot be required; but the grant sentence
	// on its own is shared by every MIT derivative, and matching on it credits them all as MIT.
	//
	// **The residual is named rather than papered over.** MIT derivatives exist that carry all
	// three hallmarks and add a clause — the JSON licence's "Good, not Evil" is the one people
	// meet — and this check would call those MIT. A blocklist of known extra clauses was rejected:
	// it cannot be complete, and a list that looks authoritative while missing the next derivative
	// is the same overclaim as matching on one sentence. What is actually promised here is
	// narrower than "this is MIT": it is "this carries MIT's hallmarks and no other licence's".
	let mitHallmarks = [
		"Permission is hereby granted, free of charge",
		"without restriction, including without limitation the rights",
		"THE SOFTWARE IS PROVIDED \"AS IS\"",
	]
	if mitHallmarks.allSatisfy(text.contains) {
		types.append("MIT")
	}

	return types
}

/// The licence file in a checkout, whichever of the six spellings the author used.
///
/// Top level only. A `LICENSE` nested in a vendored subdirectory belongs to something this
/// package embeds, not to the package, and picking one up by a recursive search would credit the
/// wrong terms.
///
/// `min()` rather than the directory's own order, which is whatever the file system hands back —
/// a package carrying both `LICENSE` and `LICENSE.txt` should generate the same file on every
/// machine.
func licenceFile(in checkout: URL) -> URL? {
	guard let names = try? FileManager.default.contentsOfDirectory(atPath: checkout.path) else { return nil }
	return
		names
		.filter { $0.range(of: #"^(licen[cs]e|copying)(\..+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil }
		.min()
		.map(checkout.appendingPathComponent)
}

// MARK: - Emitting

/// What in a licence body would stop `literal(_:indent:)` producing verbatim text, named so the
/// failure can say which one it was.
///
/// **`#"""` suppresses escapes but does not disable them.** It raises the bar to one `#`, so
/// `\#(…)` still interpolates and `\#n` still escapes. A body containing `\#(` therefore either
/// fails to compile — after this script has reported success — or, worse, evaluates and silently
/// alters text that is supposed to be reproduced exactly. Rejecting the whole `\#` introducer
/// rather than just `\#(` is deliberate: every escape at this delimiter depth starts with it, and
/// a licence has no reason to contain the sequence at all.
///
/// The fix, should a licence ever contain one of these, is another `#` on both delimiters — a
/// decision to take deliberately, rather than one to discover from a compile error in a
/// nine-hundred-line generated file.
func rawLiteralHazard(in text: String) -> String? {
	if text.contains("\"\"\"#") { return "the raw string terminator \"\"\"#" }
	if text.contains("\\#") { return "the raw string escape introducer \\#" }
	return nil
}

/// One licence, as the generated file writes it.
struct Entry {
	let name: String
	let text: String
	let type: String
	let version: String?
}

/// Renders a licence body as an indented raw multi-line literal.
///
/// Raw (`#"""`) so that backslashes and quotes in the text — Apache-2.0 has both — need no
/// escaping, and multi-line so the generated file diffs a line at a time rather than as one
/// unreadable string per package.
///
/// Every line carrying text is prefixed with the closing delimiter's indentation, because Swift
/// strips exactly that much from each line and a line carrying less is a compile error rather
/// than a formatting quirk. **Blank lines are left genuinely empty**, which the rule exempts:
/// indenting them would commit a file full of trailing whitespace, and anything that later
/// trimmed it would silently stop the file compiling.
func literal(_ text: String, indent: String) -> String {
	let body =
		text
		.replacingOccurrences(of: "\r\n", with: "\n")
		.trimmingCharacters(in: .whitespacesAndNewlines)
		.split(separator: "\n", omittingEmptySubsequences: false)
		.map { $0.allSatisfy(\.isWhitespace) ? "" : indent + $0 }
		.joined(separator: "\n")
	return "#\"\"\"\n\(body)\n\(indent)\"\"\"#"
}

// MARK: - Run

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let checkouts = root.appendingPathComponent(".build/checkouts")

guard FileManager.default.fileExists(atPath: checkouts.path) else {
	// SwiftPM makes these; Xcode builds this package through Tuist and never populates `.build`,
	// so on a fresh clone the checkouts are genuinely absent rather than stale.
	FileHandle.standardError.write(
		Data("error: \(checkouts.path) is missing — run `swift package resolve` first.\n".utf8)
	)
	exit(1)
}

let resolved = try JSONDecoder().decode(
	Resolved.self,
	from: Data(contentsOf: root.appendingPathComponent("Package.resolved"))
)

var entries: [Entry] = []
var failures: [String] = []

for pin in resolved.pins {
	// SwiftPM names a checkout directory after the repository, which is also the name the package
	// is known by. `identity` is lower-cased, so it would render `grdb.swift` and `tca26`.
	//
	// Only a trailing `.git` comes off. `deletingPathExtension()` would take `.swift` off
	// `GRDB.swift` and go looking for a checkout that does not exist.
	let name = URL(fileURLWithPath: pin.location).lastPathComponent
		.replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
	let checkout = checkouts.appendingPathComponent(name)

	// Checked before the licence file, so a checkout SwiftPM named something this script did not
	// predict reads as the missing directory it is. Folded into "no licence file", it would hand
	// a package in `statedTerms` its hand-written entry off a directory nobody ever looked in.
	var isDirectory: ObjCBool = false
	guard FileManager.default.fileExists(atPath: checkout.path, isDirectory: &isDirectory), isDirectory.boolValue else {
		failures.append("\(name): no checkout at \(checkout.path)")
		continue
	}

	// A licence file and a hand-written entry are alternatives, so exactly one of the four
	// combinations is a package this script can credit. `statedTerms` is a human having read a
	// repository that had nothing to read: once the package ships a licence file that reading is
	// stale, and silently preferring either one is how a screen ends up stating terms the package
	// has since replaced.
	let credit: (text: String, type: String)
	switch (licenceFile(in: checkout), statedTerms[name]) {
	case (let file?, nil):
		let text = try String(contentsOf: file, encoding: .utf8)
		let types = licenceTypes(in: text)
		guard types.count == 1, let type = types.first else {
			failures.append(
				types.isEmpty
					? "\(name): \(file.lastPathComponent) matches no licence this script knows"
					: "\(name): \(file.lastPathComponent) matches \(types.joined(separator: " and ")) — say which one applies"
			)
			continue
		}
		credit = (text, type)

	case (nil, let stated?):
		credit = (stated.text, stated.type)

	case (nil, nil):
		failures.append("\(name): no licence file in \(checkout.path), and no stated terms for it in this script")
		continue

	case (let file?, _?):
		failures.append("\(name): now ships \(file.lastPathComponent) — delete its `statedTerms` entry")
		continue
	}

	// **On the one path both sources reach**, so a hand-written entry is held to exactly what a
	// discovered file is. Validating inside the branch above let `statedTerms` past unchecked,
	// which would have made the generator report success while emitting Swift that does not
	// compile — the fail-fast promise failing quietly, which is the worst way for it to fail.
	if let hazard = rawLiteralHazard(in: credit.text) {
		failures.append("\(name): its licence text contains \(hazard)")
		continue
	}

	entries.append(Entry(name: name, text: credit.text, type: credit.type, version: pin.state.version))
}

guard failures.isEmpty else {
	FileHandle.standardError.write(Data(("error: \(failures.joined(separator: "\nerror: "))\n").utf8))
	exit(1)
}

// Case-insensitively, so `GRDB.swift` sorts among the `swift-` packages rather than ahead of all
// of them — the order someone scanning the screen for a name expects.
entries.sort { $0.name.lowercased() < $1.name.lowercased() }

// Indented absolutely rather than by the literal's own stripping, because interpolating a
// multi-line string into a multi-line literal inserts it verbatim — only the literal's own lines
// are re-indented, so every line but the first would come out flush left.
let rendered = entries.map { entry in
	let version = entry.version.map { "\"\($0)\"" } ?? "nil"
	return """
		\t\tLicense(
		\t\t\tname: "\(entry.name)",
		\t\t\ttext: \(literal(entry.text, indent: "\t\t\t")),
		\t\t\ttype: "\(entry.type)",
		\t\t\tversion: \(version),
		\t\t),
		"""
}

let output = """
	//
	// Copyright © 2026 brzzdev
	// SPDX-License-Identifier: AGPL-3.0-or-later
	//
	// Generated by `just licences` from `Package.resolved`. Do not edit by hand.
	//

	/// Every package this app pins, and the terms it is used under.
	internal enum Licenses {
		internal static let all: [License] = [
	\(rendered.joined(separator: "\n"))
		]
	}

	"""

try output.write(
	to: root.appendingPathComponent("Sources/Acknowledgements/Licenses.generated.swift"),
	atomically: true,
	encoding: .utf8
)

// `disable_print` guards app code, where standard out is nowhere. This is a command-line script
// whose whole user interface is standard out, and its counterpart failure path above already
// writes to standard error.
// swiftlint:disable:next disable_print
print("Wrote \(entries.count) licences.")
