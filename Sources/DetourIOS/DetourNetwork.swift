import Foundation

class DetourNetwork {
    private static let apiUrl = URL(string: "https://godetour.dev/api/link/match-link")!

    static func matchLink(config: DetourConfig, fingerprint: ProbabilisticFingerprint, completion: @escaping @Sendable (DetourResult) -> Void) {
        guard let httpBody = try? JSONEncoder().encode(fingerprint) else {
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-ID")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            handleResponse(data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    private static func handleResponse(data: Data?, response: URLResponse?, error: Error?, completion: @escaping @Sendable (DetourResult) -> Void) {
        // Helper to print consistent error logs
        func printError(_ message: String) {
            print("🔗[Detour:NETWORK_ERROR] Error fetching deferred link: \(message)")
        }

        // 1. Transport Errors
        if let error = error {
            printError(error.localizedDescription)
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        // 2. HTTP Status Errors (400, 500, etc.)
        if !(200 ... 299).contains(httpResponse.statusCode) {
            var errorMessage = "Request failed"

            // Attempt to extract server error message
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorContent = json["error"]
            {
                if let strError = errorContent as? String {
                    errorMessage = strError
                } else if let data = try? JSONSerialization.data(withJSONObject: errorContent),
                          let strified = String(data: data, encoding: .utf8)
                {
                    errorMessage = strified
                }
            }

            printError("[\(httpResponse.statusCode)] \(errorMessage)")
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        // 3. Success Parsing
        guard let data = data else {
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let linkString = json["link"] as? String,
               let url = URL(string: linkString)
            {
                let route = LinkUtils.extractRoute(from: url)
                let result = DetourResult(processed: true, link: url, route: route)

                DispatchQueue.main.async { completion(result) }
            } else {
                // Success 200, but no link matched (standard case)
                DispatchQueue.main.async { completion(.empty()) }
            }
        } catch {
            printError(error.localizedDescription)
            DispatchQueue.main.async { completion(.empty()) }
        }
    }
}
