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

extension DetourConversion {
    private static let maxRevenue = Decimal(1_000_000_000_000)

    /// The first rule this conversion breaks, or `nil` when it is valid. The backend rejects the whole
    /// conversion when one field is off, so it is checked before sending. Lengths are UTF-16 code units,
    /// as the backend counts them.
    var validationError: String? {
        if name.isEmpty || name.utf16.count > 255 {
            return "name must be 1 to 255 characters long."
        }
        if !revenue.isFinite || revenue < 0 || revenue >= Self.maxRevenue {
            return "revenue must be a finite number, at least 0 and less than 1000000000000."
        }
        // The backend uppercases the code, so any case is fine.
        if currency.utf8.count != 3 || !currency.allSatisfy({ $0.isASCII && $0.isLetter }) {
            return "currency must be a three-letter ISO 4217 code."
        }
        if let quantity, quantity < 0 || quantity > Int(Int32.max) {
            return "quantity must be from 0 to 2147483647."
        }
        if let productId, productId.utf16.count > 255 {
            return "productId must be at most 255 characters long."
        }
        if let transactionId, transactionId.isEmpty || transactionId.utf16.count > 255 {
            return "transactionId must be 1 to 255 characters long."
        }
        return nil
    }
}
