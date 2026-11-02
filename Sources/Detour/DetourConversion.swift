import Foundation

public enum DetourRevenueType: String, Sendable {
    /// In-app purchases and subscriptions.
    case iap
    /// Revenue from ads shown in the app.
    case inAppAds = "in_app_ads"
    case other
}

/// A conversion with revenue, sent with `DetourAnalytics.logConversion`.
public struct DetourConversion: Sendable {
    public let name: String
    public let revenue: Decimal
    /// ISO 4217 code, e.g. `USD`.
    public let currency: String
    public let revenueType: DetourRevenueType
    public let productId: String?
    public let quantity: Int?
    /// The store's transaction ID. A conversion repeated with the same ID is counted once.
    public let transactionId: String?

    public init(
        name: String,
        revenue: Decimal,
        currency: String,
        revenueType: DetourRevenueType,
        productId: String? = nil,
        quantity: Int? = nil,
        transactionId: String? = nil
    ) {
        self.name = name
        self.revenue = revenue
        self.currency = currency
        self.revenueType = revenueType
        self.productId = productId
        self.quantity = quantity
        self.transactionId = transactionId
    }
}
