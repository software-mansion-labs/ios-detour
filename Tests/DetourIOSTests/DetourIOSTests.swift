@testable import DetourIOS
import Testing

@Test func extractsRouteFromVerifiedUrl() {
    let url = URL(string: "https://detour.link/app-hash/some/path?foo=1")!
    let route = LinkUtils.extractRoute(from: url)

    #expect(route == "/some/path?foo=1")
}

@Test func extractsRouteFromSchemeUrl() {
    let url = URL(string: "myapp://product/details?id=123")!
    let route = LinkUtils.extractRoute(from: url)

    #expect(route == "/product/details?id=123")
}

@Test func detectsInfrastructureUrls() {
    #expect(LinkUtils.isInfrastructureUrl("about:blank"))
    #expect(LinkUtils.isInfrastructureUrl("exp://127.0.0.1:8081"))
    #expect(!LinkUtils.isInfrastructureUrl("https://example.com/app-hash/path"))
}

@MainActor
@Test func processesRawPathWithoutUrlScheme() async {
    let result = await Detour.shared.processLink("checkout/success")

    #expect(result.route == "/checkout/success")
    #expect(result.linkType == nil)
    #expect(result.link == nil)
}
