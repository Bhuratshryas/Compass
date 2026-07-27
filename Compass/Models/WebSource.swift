//
//  WebSource.swift
//  Compass
//
//  A single retrieved source that grounds an answer, mapped to an inline
//  citation marker like [1]. Sources are only produced when the user has
//  enabled web search AND the device is online; otherwise answers are
//  generated entirely on-device with no sources.
//

import Foundation

struct WebSource: Identifiable, Equatable, Codable, Hashable {
    /// The citation number shown inline in the answer, e.g. `[1]`. 1-based.
    let id: Int
    let title: String
    let url: String
    /// Short extracted passage that supported the answer.
    let snippet: String

    var host: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
