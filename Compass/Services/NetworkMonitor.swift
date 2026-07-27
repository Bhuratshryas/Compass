//
//  NetworkMonitor.swift
//  Compass
//
//  Offline-first: the orchestrator consults this before attempting any web
//  retrieval. When the device is offline, everything falls back to purely
//  on-device generation.
//

import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Compass.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    /// Snapshot suitable for use off the main actor (best-effort).
    nonisolated var currentPathIsOnline: Bool {
        monitor.currentPath.status == .satisfied
    }
}
