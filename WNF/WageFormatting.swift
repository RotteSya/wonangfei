import Foundation

enum WNFFormat {
    static func money(_ value: Double, privacy: Bool) -> String {
        privacy ? "¥••••" : "¥\(Int(value.rounded()).formatted(.number.grouping(.automatic)))"
    }

    static func moneyDecimal(_ value: Double, privacy: Bool) -> String {
        privacy ? "¥•••.••" : String(format: "¥%.2f", value)
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours <= 0 { return "\(mins)min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h\(mins)min"
    }
}
