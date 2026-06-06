import SwiftUI

/// The coral "logged meal" card with totals and the four-up macro grid.
struct MacroCard: View {
    let meal: Meal
    var onEdit: (() -> Void)? = nil

    private var dayString: String {
        meal.createdAt.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Added to \(meal.mealType.display.lowercased()) on \(dayString)",
                      systemImage: "fork.knife")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    onEdit?()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(onEdit == nil)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(meal.calories))")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text("kcal estimated")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .foregroundStyle(.white)

            if !meal.detail.isEmpty {
                Text(meal.detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                macro("\(Int(meal.fat)) g", "fat")
                divider
                macro("\(Int(meal.carbs)) g", "carbs")
                divider
                macro("\(Int(meal.protein)) g", "protein")
                divider
                macro("\(Int(meal.fiber)) g", "fiber")
            }
            .padding(.top, 4)

            if meal.syncedToHealth {
                Label("Synced to Apple Health", systemImage: "heart.fill")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(18)
        .background(Theme.coral, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded))
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 30)
    }
}
