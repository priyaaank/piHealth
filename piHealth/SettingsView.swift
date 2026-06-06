import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var health: HealthKitManager

    @State private var anthropicDraft = ""
    @State private var openAIDraft = ""
    @State private var showKey = false

    private func draft(for provider: LLMProvider) -> Binding<String> {
        switch provider {
        case .anthropic: return $anthropicDraft
        case .openai: return $openAIDraft
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Use", selection: $settings.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Group {
                            if showKey {
                                TextField(settings.provider.keyPlaceholder, text: draft(for: settings.provider))
                            } else {
                                SecureField(settings.provider.keyPlaceholder, text: draft(for: settings.provider))
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(Theme.softText)
                        }
                    }
                } header: {
                    Text("\(settings.provider.displayName) API Key")
                } footer: {
                    Text("Stored securely in the device Keychain. \(settings.provider.consoleHint) Keys for both providers are saved independently.")
                }

                Section("Model") {
                    Picker("Model", selection: settings.bindingForModel(settings.provider)) {
                        ForEach(settings.provider.models) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                }

                Section("Configured providers") {
                    ForEach(LLMProvider.allCases) { provider in
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            if hasKey(provider) {
                                Label("Key set", systemImage: "checkmark.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.green)
                                    .font(.system(.subheadline, design: .rounded))
                            } else {
                                Text("Not set").foregroundStyle(Theme.softText)
                            }
                        }
                    }
                }

                Section("Daily goal") {
                    Stepper(value: $settings.calorieGoal, in: 1000...5000, step: 50) {
                        HStack {
                            Text("Calories")
                            Spacer()
                            Text("\(settings.calorieGoal) kcal")
                                .foregroundStyle(Theme.softText)
                        }
                    }
                }

                Section {
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                            .foregroundStyle(Theme.coral)
                        Spacer()
                        if !health.isAvailable {
                            Text("Unavailable").foregroundStyle(Theme.softText)
                        } else if health.isAuthorized {
                            Text("Connected").foregroundStyle(.green)
                        } else {
                            Button("Connect") {
                                Task { await health.requestAuthorization() }
                            }
                        }
                    }
                } footer: {
                    Text("Logged meals are written to Health as energy, protein, carbs, fat, fiber, sugar, and sodium.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        commitDrafts()
                        dismiss()
                    }
                }
            }
            .onAppear {
                anthropicDraft = settings.anthropicKey
                openAIDraft = settings.openAIKey
            }
        }
    }

    private func hasKey(_ provider: LLMProvider) -> Bool {
        let live = settings.key(for: provider)
        let draft = (provider == .anthropic ? anthropicDraft : openAIDraft)
        return !(draft.isEmpty ? live : draft).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commitDrafts() {
        settings.setKey(anthropicDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .anthropic)
        settings.setKey(openAIDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .openai)
    }
}
