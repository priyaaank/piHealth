import SwiftUI
import SwiftData

/// A sheet of the user's most-logged foods. Tapping one logs it instantly,
/// reusing its cached macros — no LLM call. Ranked by use count, then recency.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\FoodTemplate.useCount, order: .reverse),
                  SortDescriptor(\FoodTemplate.lastUsedAt, order: .reverse)])
    private var templates: [FoodTemplate]

    /// We surface only the most popular handful, not an exhaustive history.
    private static let maxShown = 12

    var onPick: (FoodTemplate) -> Void

    private var popular: [FoodTemplate] { Array(templates.prefix(Self.maxShown)) }

    var body: some View {
        NavigationStack {
            Group {
                if popular.isEmpty {
                    ContentUnavailableView(
                        "No favorites yet",
                        systemImage: "bolt.slash",
                        description: Text("Foods you log will show up here so you can re-add them with one tap.")
                    )
                } else {
                    List {
                        Section("Tap to add — no analysis needed") {
                            ForEach(popular) { template in
                                Button {
                                    onPick(template)
                                    dismiss()
                                } label: {
                                    row(template)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: remove)
                        }
                    }
                }
            }
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ template: FoodTemplate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.darkGreen)
                Text("\(Int(template.calories)) kcal · P \(Int(template.protein))g · C \(Int(template.carbs))g · F \(Int(template.fat))g")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.softText)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.coral)
        }
        .padding(.vertical, 4)
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            context.delete(popular[index])
        }
        try? context.save()
    }
}
