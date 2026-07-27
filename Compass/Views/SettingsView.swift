//
//  SettingsView.swift
//  Compass
//
//  Lets the user opt into web search (off by default) and, optionally, supply a
//  Brave Search API key for higher-quality cited results. Clearly discloses the
//  privacy trade-off: when web search is on and the device is online, the user's
//  questions are sent to the chosen search provider.
//

import SwiftUI

struct SettingsView: View {
    let reasonerName: String

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable web search", isOn: $settings.webSearchEnabled)
                        .tint(CompassTheme.primary)
                } header: {
                    Text("Web search")
                } footer: {
                    Text("Off by default. When ON and you're online, Compass may send your question to a search provider to retrieve sources and cite them. When OFF — or when you're offline — every answer is generated entirely on your device and nothing leaves your phone.")
                }

                if settings.webSearchEnabled {
                    Section {
                        SecureField("Brave Search API key (optional)", text: $settings.braveAPIKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    } header: {
                        Text("Search provider")
                    } footer: {
                        Text(settings.braveAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "Using DuckDuckGo (no key required). Add a Brave Search API key for broader, higher-quality results and citations."
                             : "Using Brave Search.")
                    }
                }

                Section {
                    LabeledContent("On-device model", value: reasonerName)
                    LabeledContent("Network", value: network.isOnline ? "Online" : "Offline")
                } header: {
                    Text("Status")
                } footer: {
                    Text("Apple Intelligence is used for reasoning and synthesis when available. Otherwise Compass uses a lightweight on-device fallback so the app always works.")
                }

                Section {
                    Text("Privacy: Compass does not collect analytics or track you. Conversations are stored only on this device. The only time data leaves your device is when you turn web search on and are online, in which case your search query is sent to the provider you selected above.")
                        .font(.footnote)
                        .foregroundStyle(CompassTheme.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CompassTheme.primary)
                }
            }
        }
    }
}
