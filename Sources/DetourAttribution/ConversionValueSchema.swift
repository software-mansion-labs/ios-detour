import Detour
import Foundation

enum CoarseValue: String, Decodable {
    case low
    case medium
    case high
}

/// The rules from `GET /api/sdk/conversion-value-schema` that map a conversion to an
/// SKAdNetwork / AdAttributionKit conversion value.
struct ConversionValueSchema: Decodable, Equatable {
    struct Rule: Decodable, Equatable {
        struct Condition: Decodable, Equatable {
            let revenueGte: Decimal?
            // PROVISIONAL: the currency sits in the rule's condition (decision of 05.11); the
            // contract still lists one currency for the whole schema as an open question.
            let currency: String?
            let countGte: Int?

            enum CodingKeys: String, CodingKey {
                case revenueGte = "revenue_gte"
                case currency
                case countGte = "count_gte"
            }
        }

        let event: String
        let condition: Condition?
        let fine: Int
        let coarse: CoarseValue?
        let lock: Bool?
        let priority: Int?

        /// `count` includes this conversion.
        func matches(_ conversion: DetourConversion, count: Int) -> Bool {
            guard event == conversion.name, (0 ... 63).contains(fine) else { return false }
            guard let condition else { return true }
            if let revenueGte = condition.revenueGte {
                if let currency = condition.currency, currency != conversion.currency { return false }
                if conversion.revenue < revenueGte { return false }
            }
            if let countGte = condition.countGte, count < countGte { return false }
            return true
        }
    }

    let version: Int?
    let rules: [Rule]

    static let empty = ConversionValueSchema(version: nil, rules: [])

    /// The rule with the highest `fine` among those the conversion matches; `priority` breaks a tie.
    func bestRule(for conversion: DetourConversion, count: Int) -> Rule? {
        rules
            .filter { $0.matches(conversion, count: count) }
            .max { ($0.fine, $0.priority ?? 0) < ($1.fine, $1.priority ?? 0) }
    }
}
