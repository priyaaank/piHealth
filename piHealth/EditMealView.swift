import SwiftUI

/// Edit a recorded meal's name, meal type, and macros. Saving writes back to
/// SwiftData and re-syncs the new values to Apple Health.
struct EditMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager

    @Bindable var meal: Meal
    var onSave: () -> Void

    // Local working copies so edits only commit on Save.
    @State private var name: String
    @State private var mealType: MealType
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var sugar: Double
    @State private var sodium: Double

    init(meal: Meal, onSave: @escaping () -> Void) {
        self.meal = meal
        self.onSave = onSave
        _name = State(initialValue: meal.name)
        _mealType = State(initialValue: meal.mealType)
        _calories = State(initialValue: meal.calories)
        _protein = State(initialValue: meal.protein)
        _carbs = State(initialValue: meal.carbs)
        _fat = State(initialValue: meal.fat)
        _fiber = State(initialValue: meal.fiber)
        _sugar = State(initialValue: meal.sugar)
        _sodium = State(initialValue: meal.sodium)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.display).tag(type)
                        }
                    }
                }

                Section("Macros") {
                    numberRow("Calories", value: $calories, unit: "kcal")
                    numberRow("Protein", value: $protein, unit: "g")
                    numberRow("Carbs", value: $carbs, unit: "g")
                    numberRow("Fat", value: $fat, unit: "g")
                    numberRow("Fiber", value: $fiber, unit: "g")
                    numberRow("Sugar", value: $sugar, unit: "g")
                    numberRow("Sodium", value: $sodium, unit: "mg")
                }

                Section {
                    HStack {
                        Image(systemName: health.isAuthorized ? "heart.fill" : "heart.slash")
                            .foregroundStyle(Theme.coral)
                        Text(health.isAuthorized
                             ? "Changes will update Apple Health."
                             : "Connect Apple Health in Settings to sync changes.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.softText)
                    }
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit)
                .foregroundStyle(Theme.softText)
                .frame(width: 38, alignment: .leading)
        }
    }

    private func commit() {
        meal.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? meal.name : name
        meal.mealType = mealType
        meal.calories = max(0, calories)
        meal.protein = max(0, protein)
        meal.carbs = max(0, carbs)
        meal.fat = max(0, fat)
        meal.fiber = max(0, fiber)
        meal.sugar = max(0, sugar)
        meal.sodium = max(0, sodium)
    }
}
