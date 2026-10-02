import Foundation

struct TopTalker: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let download: Double
    let upload: Double
    var total: Double { download + upload }
}

protocol TopTalkersProviding {
    func currentTalkers() -> [TopTalker]
}

/// Sandbox-safe stand-in: ranks network interfaces by throughput.
/// True per-app talkers need a privileged helper — see `docs/TOP_TALKERS.md`.
struct InterfaceTopTalkersProvider: TopTalkersProviding {
    var rates: () -> [InterfaceRate]

    func currentTalkers() -> [TopTalker] {
        rates().map {
            TopTalker(name: $0.name, download: $0.download, upload: $0.upload)
        }
        .sorted { $0.total > $1.total }
    }
}

enum TopTalkersAvailability {
    static let perAppSupported = false
    static let statusMessage = "Per-app top talkers need a privileged helper outside the App Sandbox."
}
