// PROTOTYPE — Variant C: "The pool"
//
// The tall answer: the result at the top, and underneath it the pool it was drawn from, with the
// drawn item marked in place. A Deck reads as a deck — cards grey out one by one and the row you
// just got is highlighted where it sits.
//
// Its answer to the dead-button problem is the pool itself: even a repeated result moves the
// highlight (or, in a Deck, greys another row), so something on screen always changes. A success
// haptic marks the draw. The cost is that the sheet is nearly full height and shows the same rows
// the screen behind it already showed.

import SwiftUI

struct VariantCResultSheet: View {
	@Bindable var session: Session
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				header
				Divider()
				pool
			}
			// No title: the screen behind already named the List, and repeating it here wastes
			// the one row of chrome this variant can afford.
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.safeAreaInset(edge: .bottom) {
				Button {
					session.isExhausted ? session.reshuffle() : session.draw()
				} label: {
					Label(
						session.isExhausted ? "Reshuffle" : "Again",
						systemImage: session.isExhausted ? "shuffle" : "dice"
					)
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.padding(.horizontal)
				.padding(.vertical, 8)
				.background(.bar)
			}
		}
		.presentationDetents([.fraction(0.9)])
		.sensoryFeedback(.success, trigger: session.drawCount)
	}

	private var header: some View {
		VStack(spacing: 8) {
			if session.isExhausted {
				Text("That's the whole deck")
					.font(.title.bold())
					.multilineTextAlignment(.center)
			} else {
				if session.showsSource, let current = session.current {
					SourceLabel(item: current)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				Text(session.current?.title ?? "—")
					.font(.largeTitle.bold())
					.multilineTextAlignment(.center)
					.minimumScaleFactor(0.5)
					.lineLimit(3)
			}

			Text(session.caption)
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.horizontal, 24)
		.padding(.vertical, 28)
	}

	private var pool: some View {
		List {
			ForEach(session.pool) { item in
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text(item.title)
						if session.showsSource, let name = item.sourceName {
							Text("\(item.sourceEmoji ?? "") \(name)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					.foregroundStyle(item.isDealt && item.id != session.current?.id ? .secondary : .primary)

					Spacer()

					if item.id == session.current?.id {
						Image(systemName: "arrow.left")
							.font(.caption.weight(.bold))
							.foregroundStyle(.tint)
					} else if item.isDealt {
						Image(systemName: "checkmark")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.listRowBackground(item.id == session.current?.id ? Color.accentColor.opacity(0.12) : nil)
			}
		}
		.listStyle(.plain)
	}
}
