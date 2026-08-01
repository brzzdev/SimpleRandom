//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

import ProjectDescription

let tuist = Tuist(
	project: .tuist(
		// `.upToNextMajor`, not a string literal: `CompatibleXcodeVersions` is
		// `ExpressibleByStringInterpolation` and `"26.0 ..< 27.0"` silently means *exactly*
		// 26.0.0, which fails generation on any later 26.x.
		compatibleXcodeVersions: .upToNextMajor("26.0"),
	),
)
