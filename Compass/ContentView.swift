//
//  ContentView.swift
//  Compass
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConversationStore.shared
    @StateObject private var chatService: ChatServiceHolder = ChatServiceHolder()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var network = NetworkMonitor.shared
    @State private var conversationPath: [UUID] = []
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $conversationPath) {
            VStack(spacing: 0) {
                HomeView(
                    store: store,
                    conversationPath: $conversationPath,
                    onNewChat: { conversationPath.append(UUID()) },
                    onOpenSettings: { showingSettings = true }
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(reasonerName: chatService.service.reasonerName)
        }
        .preferredColorScheme(.light)
    }

    private var privacyBanner: some View {
        Text(bannerText)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(CompassTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(CompassTheme.background)
    }

    private var bannerText: String {
        if settings.webSearchEnabled {
            return network.isOnline
                ? "Web search on. On-device answers; cited sources when online."
                : "Web search on, but you're offline. Answering on-device only."
        }
        return "Private. On-device only."
    }
}

private final class ChatServiceHolder: ObservableObject {
    let service: ChatServiceProtocol = ChatServiceFactory.make()
}
