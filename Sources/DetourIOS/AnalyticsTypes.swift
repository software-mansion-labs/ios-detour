import Foundation

public enum DetourEventName: String, CaseIterable {
    case login = "login"
    case search = "search"
    case share = "share"
    case signUp = "sign_up"
    case tutorialBegin = "tutorial_begin"
    case tutorialComplete = "tutorial_complete"
    case reEngage = "re_engage"
    case invite = "invite"
    case openedFromPushNotification = "opened_from_push_notification"
    case addPaymentInfo = "add_payment_info"
    case addShippingInfo = "add_shipping_info"
    case addToCart = "add_to_cart"
    case removeFromCart = "remove_from_cart"
    case refund = "refund"
    case viewItem = "view_item"
    case beginCheckout = "begin_checkout"
    case purchase = "purchase"
    case adImpression = "ad_impression"
}

struct AnalyticsEventPayload {
    let eventName: String
    let data: [String: Any]?
    let isRetention: Bool
}
