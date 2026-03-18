//
//  HomeView.swift
//  Compass
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var store: ConversationStore
    @Binding var conversationPath: [UUID]
    var onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            recentSection
            searchBar
        }
        .background(CompassTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        Text("Compass")
            .font(.system(.title2, design: .default).weight(.semibold))
            .foregroundStyle(CompassTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var searchBar: some View {
        Button(action: onNewChat) {
            HStack(spacing: 12) {
                Text("Ask anything…")
                    .font(.system(.body, design: .default))
                    .foregroundStyle(CompassTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(CompassTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: CompassTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CompassTheme.paddingH)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.conversations.isEmpty {
                Text("No recent conversations")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CompassTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CompassTheme.paddingH)
                    .padding(.top, 8)
            } else {
                Text("Recent")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(CompassTheme.textTertiary)
                    .padding(.horizontal, CompassTheme.paddingH)
                RecentListView(store: store, conversationPath: $conversationPath)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct RecentListView: View {
    @ObservedObject var store: ConversationStore
    @Binding var conversationPath: [UUID]

    var body: some View {
        List {
            ForEach(store.conversations) { conv in
                rowContent(for: conv)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CompassTheme.background)
    }

    private func rowContent(for conv: Conversation) -> some View {
        Button {
            conversationPath = [conv.id]
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversationTitle(conv))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(CompassTheme.textPrimary)
                        .lineLimit(1)
                    Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(CompassTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CompassTheme.textTertiary)
            }
            .padding(.vertical, CompassTheme.paddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: CompassTheme.paddingH, bottom: 0, trailing: CompassTheme.paddingH))
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(CompassTheme.separator)
        .listRowBackground(CompassTheme.background)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(id: conv.id)
                if conversationPath.first == conv.id {
                    conversationPath.removeAll()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func conversationTitle(_ conv: Conversation) -> String {
        conv.title.isEmpty ? "New chat" : conv.title
    }
}
