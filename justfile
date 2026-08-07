# Run recipes under bash with pipefail so a failing xcodebuild isn't masked by a
# successful `| xcbeautify`, which would otherwise let a red build report green.
set shell := ["bash", "-euo", "pipefail", "-c"]

destination := "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5"
scheme := "SimpleRandom"
# Xcode refuses to build with a Swift macro plugin until someone has approved it in the
# UI, and this graph brings several. There is nothing to click on a fresh clone, which is
# why this belongs to every Xcode invocation rather than to CI.
skip_macro_validation := "-skipMacroValidation"
workspace := "SimpleRandom.xcworkspace"

# List available recipes
default:
	@just --list

# Build the app and every module
build: ensure-generated
	xcodebuild -workspace {{ workspace }} -scheme {{ scheme }} -destination '{{ destination }}' {{ skip_macro_validation }} build | xcbeautify

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
	xcodebuild -workspace {{ workspace }} -scheme {{ scheme }} -destination '{{ destination }}' {{ skip_macro_validation }} test | xcbeautify
