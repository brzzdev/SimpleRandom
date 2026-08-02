//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

/// A seeded linear congruential generator, for tests that need a draw to come out the same
/// way twice.
///
/// Every Point-Free doc comment writes `LCRNG(seed: 0)`, but `LCRNG` is a `private struct`
/// inside swift-dependencies' own test file — so it is written locally here, and shared
/// with nothing: any other target that needs one carries its own ten lines rather than a
/// support library being invented to hold them (ADR-0019).
///
/// It lands ahead of its callers. The draws it seeds are this target's whole subject, and
/// they arrive with the randomise sheet (#21, #24).
///
/// Determinism is the whole point, so the constants are Knuth's MMIX and may not be
/// changed: a test that seeds this asserts against the sequence it produces.
struct LCRNG: RandomNumberGenerator {
	private var seed: UInt64

	init(seed: UInt64 = 0) {
		self.seed = seed
	}

	mutating func next() -> UInt64 {
		seed = 6_364_136_223_846_793_005 &* seed &+ 1_442_695_040_888_963_407
		return seed
	}
}
