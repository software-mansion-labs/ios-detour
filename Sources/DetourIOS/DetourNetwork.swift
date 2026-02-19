import Foundation

class DetourNetwork {
    
    private static func logAndFail(
        _ message: String,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        // 🔗 Standardized Library Prefix
        print("🔗 [Detour] ❌ \(message)")
        
        // Always dispatch back to main thread
        DispatchQueue.main.async {
            completion(.empty())
        }
    }

    static func matchLink(config: DetourConfig, fingerprint: ProbabilisticFingerprint, completion: @escaping @Sendable (DetourResult) -> Void) {
        
        guard let apiUrl = DetourConstants.apiUrl else {
            logAndFail("Configuration Error: Invalid API URL", completion: completion)
            return
        }
        
        let httpBody: Data
        do {
            httpBody = try JSONEncoder().encode(fingerprint)
        } catch {
            
            logAndFail("Encoding Error: Failed to encode fingerprint - \(error.localizedDescription)", completion: completion)
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
        if let transportError = error {
            logAndFail("Network Error: \(transportError.localizedDescription)", completion: completion)
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
            if let errorData = data,
               let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let errorContent = json["error"]
            {
                if let strError = errorContent as? String {
                    errorMessage = strError
                } else if let errorBytes = try? JSONSerialization.data(withJSONObject: errorContent),
                          let strified = String(data: errorBytes, encoding: .utf8)
                {
                    errorMessage = strified
                }
            }

            logAndFail("Server Error: \(errorMessage)", completion: completion)
            return
        }

        // 3. Success Parsing
        guard let responseData = data else {
            logAndFail("Parsing Error: Response data was nil", completion: completion)
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
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
            logAndFail("JSON Parsing Error: \(error.localizedDescription)", completion: completion)
        }
    }
}
