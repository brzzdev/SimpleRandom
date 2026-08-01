// PROTOTYPE — Variant A: "Centre stage"
//
// The obvious answer. A medium detent, the result alone in the middle at display size, Again
// underneath it. Nothing else is on screen, so the still frame is all result.
//
// Its answer to the dead-button problem is haptics alone: a medium impact on every draw, and
// nothing visual changes when a re-roll repeats itself. If that is enough, A is the cheapest
// thing that works. If it is not, A is the variant that proves it.

import SwiftUI

struct VariantAResultSheet: View {
	@Bindable var session: Session
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			Spacer(minLength: 0)

			if session.isExhausted {
				exhausted
			} else {
				result
			}

			Spacer(minLength: 0)
			buttons
		}
		.padding(24)
		.frame(maxWidth: .infinity)
		.presentationDetents([.medium])
		.presentationDragIndicator(.visible)
		.sensoryFeedback(.impact(weight: .medium), trigger: session.drawCount)
	}

	private var result: some View {
		VStack(spacing: 10) {
			if session.showsSource, let current = session.current {
				SourceLabel(item: current)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			Text(session.current?.title ?? "—")
				.font(.largeTitle.bold())
				.multilineTextAlignment(.center)
				.minimumScaleFactor(0.5)
				.lineLimit(4)
				.contentTransition(.identity)
		}
	}

	private var exhausted: some View {
		VStack(spacing: 10) {
			Image(systemName: "rectangle.stack.badge.minus")
				.font(.largeTitle)
				.foregroundStyle(.secondary)
			Text("That's the whole deck")
				.font(.title2.bold())
			Text("Every item in \(session.scopeName) has been dealt once.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
	}

	private var buttons: some View {
		VStack(spacing: 4) {
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

			Button("Done") { dismiss() }
				.controlSize(.large)
		}
	}
}
