import Foundation

/// MagicRule 索引里的一条规则。
/// JSON 字段为 snake_case，解码器用默认 key 策略（不做转换），
/// 靠下面的 CodingKeys 显式映射：raw 值写 JSON 里的原字段名。
/// 注意：自定义 CodingKeys 的 stringValue 就是 raw 值，解码时直接拿它
/// 跟 JSON key 原样比对；如果解码器还开着 .convertFromSnakeCase，
/// JSON key 会先被转成 camelCase（如 total_line_count → totalLineCount），
/// 再也匹配不上 snake_case 的 raw 值，非可选字段一找不到就整个 decode 抛错
/// （build 22 的回归就是这么来的）。所以 CodingKeys 和解码器策略必须配套：
/// CodingKeys 写 snake_case raw 值 ↔ 解码器用默认策略。
struct MagicRule: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let chineseName: String?
    let iconURL: String?
    let description: String?
    let types: [String]
    let ruleUpdatedAt: String?
    let typeCounts: [String: Int]
    let totalLineCount: Int
    let manifest: String?
    let providers: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case chineseName = "chinese_name"
        case iconURL = "icon_url"
        case description
        case types
        case ruleUpdatedAt = "rule_updated_at"
        case typeCounts = "type_counts"
        case totalLineCount = "total_line_count"
        case manifest
        case providers
    }

    /// 显示名：有中文名显示中文名，否则显示英文名。
    var displayName: String {
        if let cn = chineseName, !cn.trimmingCharacters(in: .whitespaces).isEmpty {
            return cn
        }
        return name
    }

    /// 是否有独立的中文名（详情页同时展示英文名时用）。
    var hasSeparateChineseName: Bool {
        guard let cn = chineseName, !cn.isEmpty else { return false }
        return cn != name
    }

    var updatedDate: Date? {
        guard let s = ruleUpdatedAt else { return nil }
        return MagicRule.isoFormatter.date(from: s)
    }

    /// 类型按行数从大到小排序。
    var sortedTypeCounts: [(key: String, value: Int)] {
        typeCounts.sorted { $0.value > $1.value }
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}

/// manifest.json 里的一个订阅文件（artifact）。
/// 比如 Telegram/Loon 的 manifest 有 3 个：完整规则、DOMAIN-SET、RULE-SET。
/// 字段来自 manifest.json 的 artifacts 数组；`ext` 用于挑 .list 文件导入。
struct RuleArtifact: Identifiable, Hashable {
    let key: String
    let label: String
    let url: URL
    let ext: String?
    let role: String?
    let recommended: Bool

    var id: String { key }
}

/// 单个客户端的索引文件：`{client, generated_at, rules: [...]}`。
/// 跟 MagicRule 一样用显式 CodingKeys（raw 值为 JSON 原字段名），
/// 因为解码器是默认 key 策略，不做 snake_case 转换。
struct ClientIndex: Codable {
    let client: String
    let generatedAt: String?
    let rules: [MagicRule]

    enum CodingKeys: String, CodingKey {
        case client
        case generatedAt = "generated_at"
        case rules
    }
}

/// 客户端轻量摘要：首页只需要名字、规则条数、最近更新时间。
/// 启动时只解摘要（不解 11,841 条规则内容），首页才能立刻出现；
/// 点进某客户端二级页时再后台解码该客户端的完整规则列表。
struct ClientSummary: Equatable {
    let client: String
    let ruleCount: Int
    let generatedAt: Date?
}

/// 11 个客户端，顺序与 MagicRule 站点一致。
enum MagicRuleClient {
    static let all: [String] = [
        "QuantumultX", "Loon", "Shadowrocket", "Surge", "SingBox",
        "Egern", "Mihomo", "Stash", "Surfboard", "AdGuard", "Anywhere",
    ]

    /// 每个客户端的主题色（用于选择器与图标底色）。
    static func color(for client: String) -> String {
        switch client {
        case "QuantumultX": return "blue"
        case "Loon": return "teal"
        case "Shadowrocket": return "purple"
        case "Surge": return "orange"
        case "SingBox": return "indigo"
        case "Egern": return "green"
        case "Mihomo": return "pink"
        case "Stash": return "cyan"
        case "Surfboard": return "mint"
        case "AdGuard": return "red"
        case "Anywhere": return "brown"
        default: return "gray"
        }
    }
}

/// 数字格式化：290039 → "29.0万"。
enum CountFormat {
    static func lines(_ n: Int) -> String {
        if n >= 10000 {
            let v = Double(n) / 10000.0
            return String(format: "%.1f万行", v)
        }
        return "\(n) 行"
    }

    static func plain(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// 日期格式化：2026-11-11T15:04:16Z → "11-11 15:04"。
enum DateFormat {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func short(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return short.string(from: date)
    }

    static func full(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return full.string(from: date)
    }
}
