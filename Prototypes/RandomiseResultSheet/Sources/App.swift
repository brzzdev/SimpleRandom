// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/11
//
// Three takes on the sheet that shows a random element, over a backdrop borrowed from the
// variant A answer to #10 so detents can be judged against real content.
//
//   A — Centre stage      medium detent, the result alone and large, Again below it
//   B — Peek bar          short detent, the List still visible and live behind, dice to re-roll
//   C — The pool          tall detent, the result over the pool it came from, which visibly changes
//
// The dark strip at the top is prototype chrome, not app design: ‹ › cycle the variant, the menu
// picks the scenario, Aa forces the largest accessibility text size, and ☾ flips the appearance.

import SwiftUI

enum Variant: String, CaseIterable {
	case a = "A", b = "B", c = "C"

	var name: String {
		switch self {
		case .a: "Centre stage"
		case .b: "Peek bar"
		case .c: "The pool"
		}
	}
}

/// Launch args, so screenshots can be taken without tapping: `--variant B --scenario deck --dark --big`.
enum LaunchArgs {
	static let arguments = ProcessInfo.processInfo.arguments

	static var variant: Variant {
		guard let index = arguments.firstIndex(of: "--variant"), index + 1 < arguments.count else { return .a }
		return Variant(rawValue: arguments[index + 1]) ?? .a
	}

	static var scenario: Scenario {
		guard let index = arguments.firstIndex(of: "--scenario"), index + 1 < arguments.count else { return .plain }
		let name = arguments[index + 1].lowercased()
		return Scenario.allCases.first { "\($0)".lowercased() == name } ?? .plain
	}

	static var isBig: Bool { arguments.contains("--big") }
	static var isDark: Bool { arguments.contains("--dark") }
	static var opensSheet: Bool { arguments.contains("--sheet") }
	/// Draws until the Deck runs out, so the exhausted state can be screenshotted directly.
	static var exhausts: Bool { arguments.contains("--exhaust") }
}

@main
struct PrototypeApp: App {
	var body: some Scene {
		WindowGroup {
			PrototypeRoot()
		}
	}
}

struct PrototypeRoot: View {
	@State private var variant = LaunchArgs.variant
	@State private var scenario = LaunchArgs.scenario
	@State private var isBig = LaunchArgs.isBig
	@State private var isDark = LaunchArgs.isDark
	@State private var session = LaunchArgs.scenario.makeSession()
	@State private var isPresenting = false

	var body: some View {
		VStack(spacing: 0) {
			chrome
			Backdrop(session: session, scenario: scenario, present: present)
				.dynamicTypeSize(isBig ? .accessibility3 : .large)
				.sheet(isPresented: $isPresenting) {
					switch variant {
					case .a: VariantAResultSheet(session: session)
					case .b: VariantBResultSheet(session: session)
					case .c: VariantCResultSheet(session: session)
					}
				}
		}
		.preferredColorScheme(isDark ? .dark : .light)
		.task {
			if LaunchArgs.opensSheet { present() }
		}
	}

	private func present() {
		if session.isExhausted {
			session.reshuffle()
		} else {
			session.open()
		}
		if LaunchArgs.exhausts, session.drawMode == .deck {
			while !session.isExhausted { session.draw() }
		}
		isPresenting = true
	}

	private var chrome: some View {
		HStack(spacing: 10) {
			Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
			Text("\(variant.rawValue) — \(variant.name)")
				.font(.footnote.weight(.semibold))
				.frame(maxWidth: .infinity)
			Button { cycle(1) } label: { Image(systemName: "chevron.right") }

			Menu {
				Picker("Scenario", selection: $scenario) {
					ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
				}
			} label: {
				Image(systemName: "square.stack.3d.up")
			}

			Button { isBig.toggle() } label: {
				Image(systemName: isBig ? "textformat.size.larger" : "textformat.size")
			}
			Button { isDark.toggle() } label: {
				Image(systemName: isDark ? "moon.fill" : "sun.max")
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.foregroundStyle(.white)
		.background(.black)
		.onChange(of: scenario) { _, new in session = new.makeSession() }
	}

	private func cycle(_ step: Int) {
		let all = Variant.allCases
		let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
		variant = all[index]
	}
}

// MARK: - Backdrop

/// The screen the sheet is presented from — variant A of #10, reduced to what matters here:
/// the rows behind the sheet and the pinned Randomise button.
struct Backdrop: View {
	@Bindable var session: Session
	let scenario: Scenario
	let present: () -> Void

	var body: some View {
		NavigationStack {
			List {
				ForEach(session.pool) { item in
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							Text(item.title)
								.foregroundStyle(item.isDealt ? .secondary : .primary)
							if session.showsSource, let name = item.sourceName {
								Text("\(item.sourceEmoji ?? "") \(name)")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						Spacer()
						if item.isDealt {
							Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
						}
					}
				}
			}
			.navigationTitle(scenario.backdropTitle)
			.navigationBarTitleDisplayMode(.inline)
			.safeAreaInset(edge: .bottom) {
				VStack(spacing: 6) {
					Button(action: present) {
						Label(session.isExhausted ? "Reshuffle" : "Randomise", systemImage: "dice")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)

					Text(session.caption)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.horizontal)
				.padding(.vertical, 8)
				.background(.bar)
			}
		}
	}
}

// MARK: - Shared bits

extension Session {
	/// The line #10 settled for a row and the pinned bar: item count, or deck progress.
	var caption: String {
		switch (drawMode, total) {
		case (.independent, 1): "1 item"
		case (.independent, let count): "\(count) items"
		case (.deck, let count): "Deck · \(remaining) of \(count) left"
		}
	}
}

/// The Combine path's provenance line — #7 made it load-bearing, because two member Lists can
/// hold the same Item title and nothing deduplicates them.
struct SourceLabel: View {
	let item: PoolItem

	var body: some View {
		if let name = item.sourceName {
			HStack(spacing: 4) {
				if let emoji = item.sourceEmoji { Text(emoji) }
				Text(name)
			}
		}
	}
}
