//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Foundation

/// What the `About` section's version row shows, and what tapping it copies.
public struct AppVersion: Equatable, Sendable {
	public let build: String
	public let marketing: String

	/// `1.0.0 (1)` — the value, not the row's label.
	///
	/// Not localisable, and deliberately so: it is a diagnostic string headed for a bug
	/// report, and what is wanted there is the version rather than the word "Version". The
	/// row's visible text is a localised phrase built around the same two fields.
	public var formatted: String {
		"\(marketing) (\(build))"
	}
}

extension AppVersion {
	/// This build's version, read from `Bundle.main` — the app bundle, not this target's,
	/// because that is where the two keys Xcode fills in live.
	///
	/// The fallback is unreachable in a real app build: `Project.swift` puts both keys in the
	/// generated `Info.plist`. It exists so the whole `About` section is not an optional to
	/// unwrap for something that cannot be missing.
	public static let current = AppVersion(
		build: Bundle.main.infoString(for: "CFBundleVersion"),
		marketing: Bundle.main.infoString(for: "CFBundleShortVersionString"),
	)
}

extension Bundle {
	fileprivate func infoString(for key: String) -> String {
		object(forInfoDictionaryKey: key) as? String ?? "—"
	}
}
