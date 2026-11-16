import Detour
import Foundation
import StoreKit
#if canImport(AdAttributionKit)
// Weak, so an app that supports iOS before 17.4 still launches there without the framework.
@_weakLinked import AdAttributionKit
#endif

/// Sets the conversion value in SKAdNetwork and, from iOS 17.4, AdAttributionKit.
/// Both return whether SKAdNetwork took the value; AdAttributionKit only follows it.
protocol PostbackUpdating: Sendable {
    func register() async -> Bool
    @discardableResult func update(fine: Int, coarse: CoarseValue?, lock: Bool) async -> Bool
}

struct ApplePostbackUpdater: PostbackUpdating {
    func register() async -> Bool {
        if #available(iOS 15.4, *) {
            return await update(fine: 0, coarse: nil, lock: false)
        }
        SKAdNetwork.registerAppForAdNetworkAttribution()
        return true
    }

    @discardableResult func update(fine: Int, coarse: CoarseValue?, lock: Bool) async -> Bool {
        var tookValue = true
        do {
            if #available(iOS 16.1, *), let coarse {
                try await SKAdNetwork.updatePostbackConversionValue(fine, coarseValue: coarse.skAdNetwork, lockWindow: lock)
            } else if #available(iOS 15.4, *) {
                try await SKAdNetwork.updatePostbackConversionValue(fine)
            } else {
                SKAdNetwork.updateConversionValue(fine)
            }
        } catch {
            tookValue = false
            DetourAttributionHost.logWarning("[Detour:ATTRIBUTION] SKAdNetwork update failed: \(error.localizedDescription)")
        }

        #if canImport(AdAttributionKit)
        if #available(iOS 17.4, *) {
            do {
                if let coarse {
                    try await Postback.updateConversionValue(fine, coarseConversionValue: coarse.adAttributionKit, lockPostback: lock)
                } else {
                    try await Postback.updateConversionValue(fine, lockPostback: lock)
                }
            } catch {
                DetourAttributionHost.logWarning("[Detour:ATTRIBUTION] AdAttributionKit update failed: \(error.localizedDescription)")
            }
        }
        #endif
        return tookValue
    }
}

extension CoarseValue {
    @available(iOS 16.1, *)
    var skAdNetwork: SKAdNetwork.CoarseConversionValue {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }

    #if canImport(AdAttributionKit)
    @available(iOS 17.4, *)
    var adAttributionKit: AdAttributionKit.CoarseConversionValue {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
    #endif
}
