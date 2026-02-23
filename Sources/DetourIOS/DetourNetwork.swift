import Foundation

class DetourNetwork {

    private static func logAndFail(
        _ message: String,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        print("🔗 [Detour] ❌ \(message)")

        DispatchQueue.main.async {
            completion(.empty())
        }
    }

    static func matchLink(
        config: DetourConfig,
        fingerprint: ProbabilisticFingerprint,
        linkType: LinkType = .deferred,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {

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
            handleResponse(
                data: data,
                response: response,
                error: error,
                linkType: linkType,
                completion: completion
            )
        }.resume()
    }

    private static func handleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        linkType: LinkType,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        if let transportError = error {
            logAndFail("Network Error: \(transportError.localizedDescription)", completion: completion)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        if !(200 ... 299).contains(httpResponse.statusCode) {
            var errorMessage = "Request failed"

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
                DispatchQueue.main.async {
                    completion(DetourResult(processed: true, link: url, route: route, linkType: linkType))
                }
            } else {
                DispatchQueue.main.async { completion(.empty()) }
            }
        } catch {
            logAndFail("JSON Parsing Error: \(error.localizedDescription)", completion: completion)
        }
    }

    static func resolveShortLink(config: DetourConfig, url: String) async -> URL? {
        guard let endpoint = DetourConstants.resolveShortUrl else {
            return nil
        }

        guard let requestBody = try? JSONEncoder().encode(["url": url]) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-ID")
        request.httpBody = requestBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 404 { return nil }
            guard (200 ... 299).contains(httpResponse.statusCode) else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let linkString = json["link"] as? String else {
                return nil
            }

            return URL(string: linkString)
        } catch {
            return nil
        }
    }
}
