//
//  ChatView.swift
//  Compass
//

import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    var onBack: () -> Void
    var onNewChat: () -> Void

    init(chatService: ChatServiceProtocol, store: ConversationStore, conversationId: UUID, initialMessages: [ChatMessage] = [], onBack: @escaping () -> Void, onNewChat: @escaping () -> Void) {
        // Reset the underlying chat service session whenever a chat view is created,
        // so each chat starts with a fresh context.
        chatService.resetSession()
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatService: chatService, store: store, conversationId: conversationId, initialMessages: initialMessages))
        self.onBack = onBack
        self.onNewChat = onNewChat
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
                .background(CompassTheme.separator)
            InputBar(
                text: $viewModel.inputText,
                attachedImage: $viewModel.attachedImage,
                isDisabled: viewModel.isLoading,
                autoFocus: viewModel.messages.isEmpty,
                onSend: viewModel.send
            )
            .accessibilityHint(viewModel.messages.isEmpty ? "Start the conversation" : "Ask another question in this thread")
        }
        .background(CompassTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Compass")
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .foregroundStyle(CompassTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat") {
                    onNewChat()
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(CompassTheme.primary)
            }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        emptyState
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .transition(.move(edge: message.role == .user ? .trailing : .leading).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 16).id("bottom")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CompassTheme.paddingH)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            // Scroll when new messages are added.
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // And also scroll smoothly while the latest answer is streaming word by word.
            .onChange(of: viewModel.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 80)
            Text("What would you like to know?")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CompassTheme.textPrimary)
            Text("Ask a question. Everything stays on your device.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CompassTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
