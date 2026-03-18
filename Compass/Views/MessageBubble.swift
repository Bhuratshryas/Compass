//
//  MessageBubble.swift
//  Compass
//
//  Chatbot-style: user on the right, assistant on the left with wide answers.
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser {
                Spacer(minLength: 40)
                bubble
                    .frame(maxWidth: CompassTheme.bubbleMaxWidth, alignment: .trailing)
            } else {
                bubble
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 4)
    }

    private var bubble: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let attachment = message.attachedImage,
               let uiImage = UIImage(data: attachment.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: CompassTheme.bubbleMaxWidth - 32, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: CompassTheme.bubbleRadius))
            }
            if !message.content.isEmpty {
                formattedText(message.content)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(isUser ? CompassTheme.textInverse : CompassTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? CompassTheme.userBubble : CompassTheme.assistantBubble)
                    .clipShape(RoundedRectangle(cornerRadius: CompassTheme.bubbleRadius))
            }
        }
    }

    /// Render simple markdown-style bold for segments wrapped in ** **.
    private func formattedText(_ content: String) -> Text {
        let parts = content.components(separatedBy: "**")
        guard !parts.isEmpty else { return Text(content) }

        var attributed = AttributedString(parts[0])
        if parts.count > 1 {
            for index in 1..<parts.count {
                var segment = AttributedString(parts[index])
                if index % 2 == 1 {
                    segment.inlinePresentationIntent = .stronglyEmphasized
                }
                attributed += segment
            }
        }
        return Text(attributed)
    }
}
