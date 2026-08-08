# Run recipes under bash with pipefail so a failing xcodebuild isn't masked by a
# successful `| xcbeautify`, which would otherwise let a red build report green.
set shell := ["bash", "-euo", "pipefail", "-c"]

destination := "platform=iOS Simulator,name=" + sim_name + ",OS=" + sim_os
scheme := "SimpleRandom"
# The simulator every iOS destination resolves to. `latest` is right on a runner,
# whose Xcode ships one iOS runtime — so the CI image tag is the pin, and there
# is no version to bump in here. Locally it is wrong whenever an Xcode beta sits
# alongside the release, so set `IOS_SIM_OS` in a shell profile: one export
# covers every repo.
sim_name := env("IOS_SIM_DEVICE", "iPhone 17 Pro")
sim_os := env("IOS_SIM_OS", "latest")
# Xcode refuses to build with a Swift macro plugin until someone has approved it in the
# UI, and this graph brings several. There is nothing to click on a fresh clone, which is
# why this belongs to every Xcode invocation rather than to CI.
skip_macro_validation := "-skipMacroValidation"
workspace := "SimpleRandom.xcworkspace"
# Everything every xcodebuild invocation here shares, so that the action — `build`, `test`,
# `test -only-testing:` — is the only thing a recipe has to spell out, and the three cannot
# drift into building or testing different things.
xcodebuild := "xcodebuild -workspace " + workspace + " -scheme " + scheme + " -destination '" + destination + "' " + skip_macro_validation

# List available recipes
default:
	@just --list

# Build the app and every module
build: ensure-generated
	{{ xcodebuild }} build | xcbeautify

# Generate if the workspace is missing or older than the manifests that produce it.
# Existence alone is the wrong test: adding a target or changing a build setting leaves a
# workspace that still opens and still builds, just not the one you wrote.
[private]
ensure-generated:
	if [ ! -d {{ workspace }} ] || [ -n "$(find Package.swift Project.swift Tuist.swift -newer {{ workspace }} 2>/dev/null)" ]; then just generate; fi

# Regenerate the Xcode project from Project.swift
generate:
	tuist generate --no-open

# Regenerate third-party licence acknowledgements from the resolved package graph
#
# Run it whenever a dependency is added, removed or re-pinned — the app never runs the
# generator, and a stale `Licenses.generated.swift` credits the wrong versions. Forgetting
# is expected rather than guarded against: `.github/workflows/licences.yml` runs this
# weekly and opens a PR with whatever moved.
#
# `swift package resolve` first because the licence text is read from `.build/checkouts`,
# which Xcode builds never populate. `resolve` honours the pinned revisions rather than
# moving them, so this reports on the graph that is committed rather than quietly
# advancing it — `update` is the one that would.
licences:
	swift package resolve
	swift scripts/generate-licences.swift

# Lint, including the rule that guards `bundle: #bundle`
lint:
	swiftlint --quiet --strict

# Run the four test targets, via the test plan
test: ensure-generated
	{{ xcodebuild }} test | xcbeautify

# Run one test target — `just test-one RandomiseFeatureTests`
#
# A flake is measured by running one suite many times and counting:
# `for i in $(seq 20); do just test-one RandomiseFeatureTests; done`. Without this recipe that
# means reaching past `just` for xcodebuild, which this repo does not do.
test-one target: ensure-generated
	{{ xcodebuild }} test -only-testing:{{ target }} | xcbeautify
