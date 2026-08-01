// PROTOTYPE — Variant B: "Peek bar"
//
// The sheet barely covers anything: a short detent with background interaction left on, so the
// List you are drawing from stays visible and scrollable behind it. The result is leading-aligned
// at title size with a big circular dice on the trailing edge — the thumb never leaves it.
//
// Its answer to the dead-button problem is a visible counter: "Draw 4" ticks up whether or not
// the item changed, so a repeat still reads as something happening. Haptic is a light selection
// tap rather than an impact, because the sheet is a control strip, not an event.

import SwiftUI

struct VariantBResultSheet: View {
	@Bindable var session: Session
	@Environment(\.dismiss) private var dismiss

	private var detent: PresentationDetent { .height(200) }

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			if session.isExhausted {
				exhausted
			} else {
				result
			}
		}
		.padding(20)
		.frame(maxWidth: .infinity, alignment: .leading)
		.presentationDetents([detent])
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: detent))
		.sensoryFeedback(.selection, trigger: session.drawCount)
	}

	private var result: some View {
		HStack(alignment: .center, spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				caption
				Text(session.current?.title ?? "—")
					.font(.title.bold())
					.lineLimit(3)
					.minimumScaleFactor(0.6)
			}

			Spacer(minLength: 0)

			Button {
				session.draw()
			} label: {
				Image(systemName: "dice.fill")
					.font(.title)
					.frame(width: 64, height: 64)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.circle)
			.accessibilityLabel("Draw again")
		}
	}

	/// The line that changes on every draw, so a repeated result is still visibly a new draw.
	private var caption: some View {
		HStack(spacing: 6) {
			if session.showsSource, let current = session.current {
				SourceLabel(item: current)
				Text("·")
			}
			Text("Draw \(session.drawCount)")
			if session.drawMode == .deck {
				Text("· \(session.remaining) left")
			}
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}

	private var exhausted: some View {
		HStack(alignment: .center, spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Deck finished")
					.font(.caption)
					.foregroundStyle(.secondary)
				Text("All \(session.total) dealt")
					.font(.title.bold())
					.lineLimit(2)
					.minimumScaleFactor(0.6)
			}

			Spacer(minLength: 0)

			Button {
				session.reshuffle()
			} label: {
				Image(systemName: "shuffle")
					.font(.title)
					.frame(width: 64, height: 64)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.circle)
			.accessibilityLabel("Reshuffle")
		}
	}
}
