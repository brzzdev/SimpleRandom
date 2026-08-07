//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Models
public import Sharing

// `hasCompletedFirstFetch`, the second and last `@Shared(.appStorage)` key, lands with the
// CloudKit wiring (#29).

extension SharedKey where Self == AppStorageKey<Theme>.Default {
	/// The Light / Dark / System preference, defaulting to System.
	///
	/// **Device-local by decision, not by omission.** It is the one piece of state
	/// deliberately excluded from sync, because a phone in a dark room and an iPad in
	/// daylight are not the same question — and the system's own Light/Dark setting does not
	/// sync either (ADR-0005). `.appStorage` is what makes that so: the Sharing library ships
	/// no `NSUbiquitousKeyValueStore` strategy, and neither a bespoke `SharedKey` nor a
	/// `Preferences` table is worth spending on a colour scheme.
	///
	/// A type-safe key rather than `@Shared(wrappedValue: .system, .appStorage("theme"))` at
	/// each site, because there are two sites — the Settings picker that writes it and
	/// `SimpleRandomApp`, which turns it into `preferredColorScheme` — and a default repeated
	/// at both is a default that can disagree with itself.
	///
	/// `"theme"` is the `UserDefaults` key and is as good as shipped once it is: renaming it
	/// silently resets everyone's preference to System.
	public static var theme: Self {
		Self[.appStorage("theme"), default: .system]
	}
}
