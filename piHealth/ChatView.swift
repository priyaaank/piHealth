import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var health: HealthKitManager

    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query(sort: \Meal.createdAt) private var meals: [Meal]

    @State private var viewModel: ChatViewModel?
    @State private var draft = ""
    @State private var pickedImage: UIImage?
    @State private var showSettings = false
    @State private var editingMeal: Meal?

    private var consumed: Int { viewModel?.consumedToday(meals) ?? 0 }
    private var remaining: Int { max(0, settings.calorieGoal - consumed) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            conversation
            if let error = viewModel?.errorMessage {
                errorBanner(error)
            }
            Composer(text: $draft, pickedImage: $pickedImage,
                     isThinking: viewModel?.isThinking ?? false,
                     onSend: send)
            Text("AI estimates can be off. Please double-check important info.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.softText)
                .padding(.bottom, 6)
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            if viewModel == nil {
                viewModel = ChatViewModel(context: context, settings: settings, health: health)
            }
            if health.isAvailable && !health.isAuthorized {
                await health.requestAuthorization()
            }
            if ProcessInfo.processInfo.arguments.contains("-openSettings") {
                showSettings = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings).environmentObject(health)
        }
        .sheet(item: $editingMeal) { meal in
            EditMealView(meal: meal) {
                Task { await viewModel?.resync(meal: meal) }
            }
            .environmentObject(health)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.coral)
                HStack(spacing: 6) {
                    Text("\(remaining)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.darkGreen)
                    Text("kcal remaining")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.softText)
                }
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.darkGreen)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        EmptyState(configured: settings.isConfigured) { showSettings = true }
                            .padding(.top, 40)
                    }
                    ForEach(messages) { message in
                        MessageRow(message: message) { meal in
                            editingMeal = meal
                        }
                        .id(message.id)
                    }
                    if viewModel?.isThinking == true {
                        ThinkingRow().id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: viewModel?.isThinking) { _, thinking in
                if thinking == true {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.coralDeep, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 14)
            .onTapGesture { viewModel?.errorMessage = nil }
    }

    private func send() {
        let text = draft
        let image = pickedImage
        draft = ""
        pickedImage = nil
        Task {
            await viewModel?.send(text: text, image: image, history: messages, meals: meals)
        }
    }
}

// MARK: - Message rows

private struct MessageRow: View {
    let message: ChatMessage
    var onEditMeal: (Meal) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 8) {
                    if let data = message.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(Theme.body)
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Theme.coral, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.darkGreen).frame(width: 22, height: 22)
                        .overlay(Circle().fill(Theme.coral).frame(width: 9, height: 9))
                    Text(message.text)
                        .font(Theme.body)
                        .foregroundStyle(Theme.darkGreen)
                }
                if let meal = message.meal {
                    MacroCard(meal: meal) { onEditMeal(meal) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
        }
    }
}

private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.darkGreen).frame(width: 22, height: 22)
                .overlay(Circle().fill(Theme.coral).frame(width: 9, height: 9))
            ProgressView().tint(Theme.softText)
            Text("Estimating…")
                .font(Theme.body)
                .foregroundStyle(Theme.softText)
        }
    }
}

private struct EmptyState: View {
    let configured: Bool
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            Text("Tell me what you ate")
                .font(Theme.title)
                .foregroundStyle(Theme.darkGreen)
            Text("Describe a meal or snap a photo. I'll estimate the macros and sync them to Apple Health.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.softText)
                .multilineTextAlignment(.center)
            if !configured {
                Button(action: openSettings) {
                    Label("Add your API key", systemImage: "key.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.vertical, 10).padding(.horizontal, 18)
                        .background(Theme.coral, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}
