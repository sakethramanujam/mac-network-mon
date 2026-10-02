import Darwin
import Foundation

enum SpeedTestError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid speed-test URL"
        case .downloadFailed(let message): return message
        case .uploadFailed(let message): return message
        }
    }
}

struct SpeedTestResult {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let downloadBytes: Int
    let uploadBytes: Int
}

/// Cloudflare download then upload speed test.
final class SpeedTester {
    private var task: URLSessionDataTask?
    private var measID = ""

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(
        downloadBytes: Int = 20_000_000,
        uploadBytes: Int = 10_000_000,
        onPhase: @escaping (SpeedTestPhase) -> Void,
        completion: @escaping (Result<SpeedTestResult, Error>) -> Void
    ) {
        cancel()
        measID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)&measId=\(measID)") else {
            completion(.failure(SpeedTestError.invalidURL))
            return
        }

        onPhase(.download)
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 120
        Self.applyCloudflareHeaders(to: &request)

        let downloadStart = Date()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let data, error == nil, !data.isEmpty {
                let elapsed = max(Date().timeIntervalSince(downloadStart), 0.001)
                let downRate = Double(data.count) / elapsed
                self.startUpload(
                    uploadBytes: uploadBytes,
                    downloadRate: downRate,
                    downloadCount: data.count,
                    onPhase: onPhase,
                    completion: completion
                )
            } else {
                DispatchQueue.main.async {
                    completion(.failure(SpeedTestError.downloadFailed(error?.localizedDescription ?? "Download failed")))
                }
            }
        }
        task?.resume()
    }

    private func startUpload(
        uploadBytes: Int,
        downloadRate: Double,
        downloadCount: Int,
        onPhase: @escaping (SpeedTestPhase) -> Void,
        completion: @escaping (Result<SpeedTestResult, Error>) -> Void
    ) {
        guard let uploadURL = URL(string: "https://speed.cloudflare.com/__up?measId=\(measID)") else {
            DispatchQueue.main.async { completion(.failure(SpeedTestError.invalidURL)) }
            return
        }

        DispatchQueue.main.async { onPhase(.upload) }

        var payload = Data(count: uploadBytes)
        payload.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                arc4random_buf(base, uploadBytes)
            }
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = payload
        Self.applyCloudflareHeaders(to: &request)

        let uploadStart = Date()
        task = URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            let ok: Bool = {
                if error != nil { return false }
                if let status { return (200...299).contains(status) }
                return true
            }()
            DispatchQueue.main.async {
                if ok {
                    let elapsed = max(Date().timeIntervalSince(uploadStart), 0.001)
                    let upRate = Double(uploadBytes) / elapsed
                    completion(.success(SpeedTestResult(
                        downloadBytesPerSecond: downloadRate,
                        uploadBytesPerSecond: upRate,
                        downloadBytes: downloadCount,
                        uploadBytes: uploadBytes
                    )))
                } else {
                    completion(.failure(SpeedTestError.uploadFailed(
                        error?.localizedDescription ?? "Upload failed (HTTP \(status ?? 0))"
                    )))
                }
            }
        }
        task?.resume()
    }

    static func applyCloudflareHeaders(to request: inout URLRequest) {
        request.setValue("https://speed.cloudflare.com", forHTTPHeaderField: "Origin")
        request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) NetworkMon/1.5",
            forHTTPHeaderField: "User-Agent"
        )
    }
}
