import Foundation

public enum DetourEventName: String, CaseIterable {
    case login
    case search
    case share
    case signUp = "sign_up"
    case tutorialBegin = "tutorial_begin"
    case tutorialComplete = "tutorial_complete"
    case reEngage = "re_engage"
    case invite
    case openedFromPushNotification = "opened_from_push_notification"
    case addPaymentInfo = "add_payment_info"
    case addShippingInfo = "add_shipping_info"
    case addToCart = "add_to_cart"
    case removeFromCart = "remove_from_cart"
    case refund
    case viewItem = "view_item"
    case beginCheckout = "begin_checkout"
    case purchase
    case adImpression = "ad_impression"
}

/// One analytics request; `AnalyticsNetwork.send` builds its body and endpoint.
enum AnalyticsRequest {
    case event(name: String, data: [String: Any]?, at: Date)
    case retention(name: String, at: Date)
    case session(SessionManager.Event)
    case conversion(DetourConversion, at: Date)
}
