//
//  AppSettings.swift
//  Compass
//
//  User-controlled configuration. Web search is OFF by default so the app
//  keeps its on-device-only guarantee unless the user explicitly opts in.
//

import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// When true (and the device is online), the assistant may retrieve web
    /// results to ground answers with citations. When false, everything stays
    /// on-device. Default: false.
    @Published var webSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(webSearchEnabled, forKey: Keys.webSearch) }
    }

    /// Optional Brave Search API key. If present, the higher-quality Brave
    /// provider is used; otherwise the keyless DuckDuckGo provider is used.
    @Published var braveAPIKey: String {
        didSet { UserDefaults.standard.set(braveAPIKey, forKey: Keys.braveKey) }
    }

    private enum Keys {
        static let webSearch = "Compass.settings.webSearchEnabled"
        static let braveKey = "Compass.settings.braveAPIKey"
    }

    private init() {
        webSearchEnabled = UserDefaults.standard.bool(forKey: Keys.webSearch)
        braveAPIKey = UserDefaults.standard.string(forKey: Keys.braveKey) ?? ""
    }
}
