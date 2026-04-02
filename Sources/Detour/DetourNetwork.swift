import Foundation

class DetourNetwork {
    private static let tag = "DetourApiClient"

    private struct LinkResponse: Decodable {
        let link: String?
    }

    private static func applyHeaders(to request: inout URLRequest, config: DetourConfig) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(DetourConstants.sdkHeaderValue, forHTTPHeaderField: DetourConstants.sdkHeaderField)
    }

    private static func logAndFail(
        _ message: String,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        DetourLogger.error(tag, "[Detour:NETWORK_ERROR] \(message)")

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
        applyHeaders(to: &request, config: config)
        request.httpBody = httpBody

        DetourLogger.debug(tag, "Sending fingerprint to API")

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
            let response = try JSONDecoder().decode(LinkResponse.self, from: responseData)

            if let linkString = response.link,
               let url = URL(string: linkString) {
                DetourLogger.debug(tag, "Link matched successfully")
                let detourLink = LinkUtils.makeDetourLink(from: url, type: linkType)
                DispatchQueue.main.async {
                    completion(DetourResult(processed: true, link: detourLink))
                }
            } else {
                DetourLogger.debug(tag, "No matching link found")
                DispatchQueue.main.async { completion(.empty()) }
            }
        } catch {
            logAndFail("JSON Parsing Error: \(error.localizedDescription)", completion: completion)
        }
    }

    static func resolveShortLink(config: DetourConfig, url: String) async -> URL? {
        guard let endpoint = DetourConstants.resolveShortUrl else {
            DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution failed: invalid endpoint")
            return nil
        }

        let normalizedInput = LinkUtils.normalizeRawLink(url)

        guard let requestBody = try? JSONEncoder().encode(["url": url]) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config)
        request.httpBody = requestBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 404 { return nil }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution failed: \(httpResponse.statusCode)")
                return nil
            }

            let decodedResponse = try JSONDecoder().decode(LinkResponse.self, from: data)
            guard let linkString = decodedResponse.link,
                  let resolvedURL = URL(string: linkString) else {
                return nil
            }

            let normalizedResolved = LinkUtils.normalizeRawLink(resolvedURL.absoluteString)
            if normalizedResolved == normalizedInput {
                return nil
            }

            DetourLogger.debug(tag, "Short link resolved successfully")
            return resolvedURL
        } catch {
            DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution exception: \(error.localizedDescription)")
            return nil
        }
    }
}
