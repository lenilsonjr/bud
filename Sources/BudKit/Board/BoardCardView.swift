#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One bud on the board: its first picture when it embeds one, its title behind the kind's
/// mark, the trail from the board's bud down to its parent, then its when and due tags, its
/// other tags, and how many buds are inside. Read only: a click does nothing yet. The card
/// watches nothing: its picture comes in decoded, and it asks once when that is unknown.
struct BoardCardView: View {
    let card: BoardCard
    let picture: BoardPictureState
    let now: Date
    /// Asks the store for the picture; called once, when it is unknown.
    let load: () async -> Void

    private static let title = TextStyle(typeface: .text, size: 13, weight: 500)
    private static let small = TextStyle(typeface: .text, size: 11, weight: 400)
    private static let tag = TextStyle(typeface: .text, size: 11, weight: 600)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let picture = picture.picture {
                Image(decorative: picture.image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            HStack(alignment: .top, spacing: 8) {
                lead
                Text(card.title)
                    .strikethrough(card.isCancelled, color: Theme.text3)
                    .textStyle(Self.title)
                    .lineSpacing(2)
                    .foregroundStyle(card.isDone || card.isCancelled ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !card.trail.isEmpty {
                Text(card.trailText)
                    .textStyle(Self.small)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            meta
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 1, y: 1)
        .task(id: card.id) {
            if case .unknown = picture { await load() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-card")
    }

    /// The box of a to-do, filled in leaf with a tick once done; the small square of a note.
    @ViewBuilder private var lead: some View {
        Group {
            if card.isTodo {
                if card.isDone {
                    RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                        .fill(Theme.leafFill)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.onLeaf)
                        }
                } else {
                    RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                        .stroke(Theme.text3, lineWidth: 1.3)
                }
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.text3)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, height: 14)
        .frame(height: 18)
    }

    /// When in pistil, due in rose, the other tags neutral, and "6 inside" at the far right.
    private var meta: some View {
        HStack(spacing: 5) {
            if let when = card.whenText(now: now) {
                chip(when, icon: "calendar", ink: Theme.pistil, wash: Theme.pistilSoft)
            }
            if let due = card.dueText(now: now) {
                chip(due, icon: "flag", ink: Theme.rose, wash: Theme.roseSoft)
            }
            ForEach(card.tags, id: \.self) { tag in
                chip(tag, icon: nil, ink: Theme.text2, wash: Theme.raised)
            }
            Spacer(minLength: 0)
            if let inside = card.insideText {
                Text(inside)
                    .textStyle(Self.small)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
        }
    }

    private func chip(_ text: String, icon: String?, ink: Color, wash: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 11, height: 11)
            }
            Text(text)
                .textStyle(Self.tag)
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(wash, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}
#endif
