import SwiftUI
import PhotosUI

/// Bottom input bar: text field with photo, mic (dictation), and send.
struct Composer: View {
    @Binding var text: String
    @Binding var pickedImage: UIImage?
    var isThinking: Bool
    var onSend: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || pickedImage != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = pickedImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Photo attached")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.softText)
                    Spacer()
                    Button {
                        pickedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.softText)
                    }
                }
                .padding(.horizontal, 8)
            }

            HStack(spacing: 10) {
                TextField("Type a meal or message…", text: $text, axis: .vertical)
                    .font(Theme.body)
                    .focused($focused)
                    .lineLimit(1...4)
                    .foregroundStyle(Theme.darkGreen)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "camera")
                        .foregroundStyle(Theme.darkGreen.opacity(0.7))
                }

                Button(action: onSend) {
                    if isThinking {
                        ProgressView().tint(Theme.coral)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend ? Theme.coral : Theme.softText.opacity(0.5))
                    }
                }
                .disabled(!canSend || isThinking)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.bubble, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.background)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickedImage = image
                }
            }
        }
    }
}
