// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/10
//
// Three structurally different takes on the Lists tab + List detail, switchable from the
// dark strip at the top (‹ ›). That strip is prototype chrome, not app design.
//
//   A — Sheets & pinned bar   conventional HIG: toolbar +, editor sheets, full-width pinned Randomise
//   B — Inline & FAB          Reminders-like: inline text fields, no editor sheets, circular floating Randomise
//   C — Cards & header        cards you can randomise from the index, Randomise in a scrolling detail header
//
// The "Sample / Empty" toggle swaps the store so first-launch and empty states are one tap away.

import SwiftUI

enum Variant: String, CaseIterable {
	case a = "A", b = "B", c = "C"

	var name: String {
		switch self {
		case .a: "Sheets & pinned bar"
		case .b: "Inline & FAB"
		case .c: "Cards & header"
		}
	}
}

/// Launch args, so screenshots can be taken without tapping: `--variant B --detail`.
enum LaunchArgs {
	static let arguments = ProcessInfo.processInfo.arguments
	static var variant: Variant {
		guard let index = arguments.firstIndex(of: "--variant"), index + 1 < arguments.count else { return .a }
		return Variant(rawValue: arguments[index + 1]) ?? .a
	}
	static var opensDetail: Bool { arguments.contains("--detail") }
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
	@State private var isEmpty = false
	@State private var store = Store.sample()

	var body: some View {
		VStack(spacing: 0) {
			switcher
			TabView {
				Tab("Lists", systemImage: "list.bullet") {
					switch variant {
					case .a: VariantAListsTab(store: store)
					case .b: VariantBListsTab(store: store)
					case .c: VariantCListsTab(store: store)
					}
				}
				Tab("Combine", systemImage: "square.stack.3d.up") {
					NavigationStack { Text("Combine").navigationTitle("Combine") }
				}
				Tab("Settings", systemImage: "gear") {
					NavigationStack { Text("Settings").navigationTitle("Settings") }
				}
			}
		}
		.id(variant)
	}

	private var switcher: some View {
		HStack(spacing: 12) {
			Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
			VStack(spacing: 0) {
				Text("\(variant.rawValue) — \(variant.name)").font(.footnote.weight(.semibold))
			}
			.frame(maxWidth: .infinity)
			Button { cycle(1) } label: { Image(systemName: "chevron.right") }
			Button(isEmpty ? "Empty" : "Sample") {
				isEmpty.toggle()
				store = isEmpty ? .empty() : .sample()
			}
			.font(.caption.weight(.semibold))
			.buttonStyle(.bordered)
			.tint(.white)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.foregroundStyle(.white)
		.background(.black)
	}

	private func cycle(_ step: Int) {
		let all = Variant.allCases
		let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
		variant = all[index]
	}
}

// MARK: - Shared bits

/// Placeholder for the real result sheet — that's its own ticket (#11). Here only so the
/// Randomise affordance leads somewhere.
struct ResultSheetStub: View {
	let list: RandomList
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 24) {
			Text("The result sheet is issue #11").font(.footnote).foregroundStyle(.secondary)
			Text(list.items.randomElement()?.title ?? "—").font(.largeTitle.bold())
			Button("Again") {}.buttonStyle(.borderedProminent)
			Button("Done") { dismiss() }
		}
		.padding()
		.presentationDetents([.medium])
	}
}

extension RandomList {
	var subtitle: String {
		switch (drawMode, items.count) {
		case (_, 0): "No items"
		case (.independent, 1): "1 item"
		case (.independent, let count): "\(count) items"
		case (.deck, let count):
			"Deck · \(count - items.filter(\.isDealt).count) of \(count) left"
		}
	}

	var isExhausted: Bool { drawMode == .deck && !items.isEmpty && items.allSatisfy(\.isDealt) }
}
