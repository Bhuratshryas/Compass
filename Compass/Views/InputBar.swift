//
//  InputBar.swift
//  Compass
//

import SwiftUI
import PhotosUI

struct InputBar: View {
    @Binding var text: String
    @Binding var attachedImage: ChatMessage.ImageAttachment?
    var isDisabled: Bool
    var autoFocus: Bool
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        attachedImage: Binding<ChatMessage.ImageAttachment?>,
        isDisabled: Bool,
        autoFocus: Bool = false,
        onSend: @escaping () -> Void
    ) {
        _text = text
        _attachedImage = attachedImage
        self.isDisabled = isDisabled
        self.autoFocus = autoFocus
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 0) {
            if attachedImage != nil {
                attachedImageBar
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 1,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(CompassTheme.textTertiary)
                        .frame(width: 32, height: 40)
                }
                .onChange(of: selectedItems) { _, newValue in
                    loadImage(from: newValue.first)
                }

                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(CompassTheme.textPrimary)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(CompassTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: CompassTheme.inputRadius))

                Button(action: { onSend() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? CompassTheme.primary : CompassTheme.textTertiary)
                        .opacity(canSend ? 1 : 0.5)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isDisabled)
            }
            .padding(.horizontal, CompassTheme.paddingH)
            .padding(.vertical, 10)
            .background(CompassTheme.background)
        }
        .background(CompassTheme.background)
        .onAppear {
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isFocused = true
                }
            }
        }
    }

    @State private var selectedItems: [PhotosPickerItem] = []

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil
    }

    private var attachedImageBar: some View {
        HStack(spacing: 10) {
            if let att = attachedImage,
               let uiImage = UIImage(data: att.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Image attached")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CompassTheme.textSecondary)
                Spacer()
                Button {
                    attachedImage = nil
                    selectedItems = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(CompassTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, CompassTheme.paddingH)
        .padding(.vertical, 8)
        .background(CompassTheme.surface)
    }

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else {
            attachedImage = nil
            return
        }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    attachedImage = ChatMessage.ImageAttachment(data: data, id: UUID())
                }
            }
        }
    }
}
