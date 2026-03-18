//
//  ContentView.swift
//  Compass
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConversationStore.shared
    @StateObject private var chatService: ChatServiceHolder = ChatServiceHolder()
    @State private var conversationPath: [UUID] = []
    @State private var showingPrivacyPolicy = false

    var body: some View {
        Group {
            if chatService.service.isAvailable() {
                NavigationStack(path: $conversationPath) {
                    VStack(spacing: 0) {
                        HomeView(
                            store: store,
                            conversationPath: $conversationPath,
                            onNewChat: { conversationPath.append(UUID()) }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        privacyBanner
                    }
                    .navigationDestination(for: UUID.self) { id in
                        VStack(spacing: 0) {
                            ChatView(
                                chatService: chatService.service,
                                store: store,
                                conversationId: id,
                                initialMessages: store.conversation(by: id)?.messages ?? [],
                                onBack: { conversationPath.removeAll() },
                                onNewChat: { conversationPath.append(UUID()) }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            privacyBanner
                        }
                    }
                }
            } else {
                UnavailableView(message: chatService.service.availabilityMessage())
            }
        }
        .preferredColorScheme(.light)
    }

    private var privacyBanner: some View {
        Button {
            showingPrivacyPolicy = true
        } label: {
            Text("Private. On-device only.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(CompassTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(CompassTheme.background)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

private final class ChatServiceHolder: ObservableObject {
    let service: ChatServiceProtocol = ChatServiceFactory.make()
}

struct UnavailableView: View {
    let message: String

    var body: some View {
        ZStack {
            CompassTheme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Compass")
                    .font(.system(.title2, design: .default).weight(.semibold))
                    .foregroundStyle(CompassTheme.textPrimary)
                Text("Everything runs on your device. We don't collect your data.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(CompassTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CompassTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
