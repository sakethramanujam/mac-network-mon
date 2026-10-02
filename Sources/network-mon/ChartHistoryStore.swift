import Foundation

enum ChartHistoryStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NetworkMon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chart-history.json")
    }

    private struct Payload: Codable {
        var samples: [CodableSample]
    }

    private struct CodableSample: Codable {
        var date: Date
        var download: Double
        var upload: Double
    }

    static func load() -> [SpeedSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.samples.map {
            SpeedSample(date: $0.date, download: $0.download, upload: $0.upload)
        }
    }

    static func save(_ samples: [SpeedSample]) {
        let payload = Payload(samples: samples.map {
            CodableSample(date: $0.date, download: $0.download, upload: $0.upload)
        })
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
