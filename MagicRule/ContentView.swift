import SwiftUI
import UIKit

// MARK: - 设计语言：MagicRule 网页版（暖米色底 + 琥珀橙主色 + 白圆角卡片）
// 浅色：暖米底 #FAF6EC、白卡片、琥珀橙；深色：暖炭底 + 暖棕卡片 + 亮琥珀。
enum Theme {
    private static func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let bg = dyn(
        UIColor(red: 0.980, green: 0.965, blue: 0.925, alpha: 1),
        UIColor(red: 0.090, green: 0.075, blue: 0.055, alpha: 1)
    )
    static let card = dyn(
        .white,
        UIColor(red: 0.150, green: 0.125, blue: 0.105, alpha: 1)
    )
    static let cardStroke = dyn(
        UIColor(red: 0.930, green: 0.895, blue: 0.830, alpha: 1),
        UIColor(red: 0.235, green: 0.205, blue: 0.155, alpha: 1)
    )
    static let text = dyn(
        UIColor(red: 0.115, green: 0.095, blue: 0.070, alpha: 1),
        UIColor(red: 0.957, green: 0.933, blue: 0.890, alpha: 1)
    )
    static let secondary = dyn(
        UIColor(red: 0.540, green: 0.500, blue: 0.435, alpha: 1),
        UIColor(red: 0.660, green: 0.620, blue: 0.545, alpha: 1)
    )
    static let tertiary = dyn(
        UIColor(red: 0.705, green: 0.665, blue: 0.585, alpha: 1),
        UIColor(red: 0.480, green: 0.445, blue: 0.385, alpha: 1)
    )
    /// 琥珀主色（文字 / 图标用）
    static let accent = dyn(
        UIColor(red: 0.790, green: 0.540, blue: 0.025, alpha: 1),
        UIColor(red: 0.913, green: 0.663, blue: 0.230, alpha: 1)
    )
    /// 琥珀浅底（药丸、图标底）
    static let accentSoft = dyn(
        UIColor(red: 0.968, green: 0.913, blue: 0.775, alpha: 1),
        UIColor(red: 0.240, green: 0.185, blue: 0.095, alpha: 1)
    )
    /// 类型徽标底 / 字
    static let badgeBg = dyn(
        UIColor(red: 0.953, green: 0.918, blue: 0.840, alpha: 1),
        UIColor(red: 0.220, green: 0.190, blue: 0.120, alpha: 1)
    )
    static let badgeText = dyn(
        UIColor(red: 0.480, green: 0.360, blue: 0.055, alpha: 1),
        UIColor(red: 0.913, green: 0.790, blue: 0.475, alpha: 1)
    )
    /// 琥珀渐变（选中药丸、Logo 底、主按钮）
    static let amberGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.65, blue: 0.15), Color(red: 0.80, green: 0.49, blue: 0.03)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - 相对时间：4 小时前 / 昨天 / 3 天前 / 1 个月前
enum RelativeFormat {
    static func string(from date: Date?) -> String {
        guard let date else { return "未知" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        let days = Int(seconds / 86400)
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days) 天前" }
        let months = days / 30
        if months < 12 { return "\(months) 个月前" }
        return "\(months / 12) 年前"
    }
}

// MARK: - 排序：更新时间（默认）/ 名字 A-Z / 行数 / 类型数
enum RuleSort: String, CaseIterable, Identifiable {
    case updated
    case name
    case lines
    case types

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updated: return "更新"
        case .name: return "名字"
        case .lines: return "行数"
        case .types: return "类型"
        }
    }

    func sort(_ rules: [MagicRule]) -> [MagicRule] {
        switch self {
        case .updated:
            return rules.sorted {
                switch ($0.updatedDate, $1.updatedDate) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                default: return $0.name.lowercased() < $1.name.lowercased()
                }
            }
        case .name:
            return rules.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .lines:
            return rules.sorted { $0.totalLineCount > $1.totalLineCount }
        case .types:
            return rules.sorted {
                if $0.types.count != $1.types.count { return $0.types.count > $1.types.count }
                return $0.name.lowercased() < $1.name.lowercased()
            }
        }
    }
}

// MARK: - 剪贴板（带成功校验）
enum Clipboard {
    @discardableResult
    static func copy(_ string: String) -> Bool {
        UIPasteboard.general.string = string
        return UIPasteboard.general.string == string
    }
}

// MARK: - 一键导入
//
// 各客户端的规则导入 URL Scheme（已按官方文档核实）：
// - QuantumultX（官方 url-scheme.md）：quantumult-x:///add-resource?remote-resource=<url-encoded JSON>，
//   JSON 为 {"filter_remote": ["<list地址>, tag=<规则名>, force-policy=PROXY"]}，只追加不替换已有资源。
// - Loon（官方 nsloon.app 文档）：loon://import?rules=<url-encoded 规则地址>。
// - Surge：官方只有 install-config（整配置，会替换用户配置，危险）和 install-module（.sgmodule），
//   没有单条规则集的导入 Scheme，走复制兜底。
// - Stash / SingBox：只有整配置导入（stash://install-config、sing-box://import-remote-profile），
//   单条 .list 规则集无法用它们导入，走复制兜底。
// - Shadowrocket / Egern / Surfboard / Mihomo / AdGuard / Anywhere：无公开的规则导入 Scheme，走复制兜底。
enum RuleImport {
    /// 只保留 RFC 3986 不需编码的字符，其余全部百分号编码。
    /// 用于把一段 JSON 或一整条 URL 整体放进 query 参数，避免 & = 等字符截断参数。
    private static let queryValueAllowed =
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    /// 该客户端是否支持 URL Scheme 一键导入。
    static func supportsImport(client: String) -> Bool {
        client == "QuantumultX" || client == "Loon"
    }

    /// 构造某客户端的一键导入 URL；不支持的客户端返回 nil（调用方走复制兜底）。
    static func importURL(for client: String, listURL: URL, ruleName: String) -> (url: URL, appName: String)? {
        switch client {
        case "QuantumultX":
            let entry = "\(listURL.absoluteString), tag=\(ruleName), force-policy=PROXY"
            guard let jsonData = try? JSONSerialization.data(
                withJSONObject: ["filter_remote": [entry]], options: []),
                  let json = String(data: jsonData, encoding: .utf8),
                  let encoded = json.addingPercentEncoding(withAllowedCharacters: queryValueAllowed),
                  let url = URL(string: "quantumult-x:///add-resource?remote-resource=\(encoded)") else {
                return nil
            }
            return (url, "QuantumultX")
        case "Loon":
            guard let encoded = listURL.absoluteString
                .addingPercentEncoding(withAllowedCharacters: queryValueAllowed),
                  let url = URL(string: "loon://import?rules=\(encoded)") else {
                return nil
            }
            return (url, "Loon")
        default:
            return nil
        }
    }

    /// 可复制/分享的链接：优先 manifest，其次第一个 provider。
    static func shareURL(for rule: MagicRule) -> URL? {
        if let m = rule.manifest, let url = URL(string: m) { return url }
        return rule.providers.compactMap { URL(string: $0) }.first
    }

    /// 把一条规则解析成可导入的 .list 地址：
    /// 优先读 manifest.json 的 artifacts（取 ext 为 list 的那条），
    /// 拿不到时退回第一个 raw.githubusercontent.com 的 provider，再拿不到退回第一个 provider。
    static func resolveListURL(for rule: MagicRule) async -> URL? {
        if let manifestString = rule.manifest,
           let manifestURL = URL(string: manifestString) {
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = 10
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let artifacts = json["artifacts"] as? [[String: Any]], !artifacts.isEmpty {
                let pick = artifacts.first(where: { ($0["ext"] as? String) == "list" }) ?? artifacts[0]
                if let urlString = pick["url"] as? String, let url = URL(string: urlString) {
                    return url
                }
            }
        }
        for p in rule.providers where p.contains("raw.githubusercontent.com") {
            if let url = URL(string: p) { return url }
        }
        if let first = rule.providers.first, let url = URL(string: first) {
            return url
        }
        return nil
    }

    /// 一键导入：返回一句 Toast 文案。
    /// 对应 App 能打开时直接打开；没装或 Scheme 打不开时复制 .list 链接并提示手动导入。
    static func attemptImport(client: String, rule: MagicRule) async -> String {
        guard let listURL = await resolveListURL(for: rule) else {
            if let url = shareURL(for: rule) {
                return Clipboard.copy(url.absoluteString) ? "已复制链接，请手动导入" : "复制失败，请重试"
            }
            return "没有可导入的链接"
        }
        if let (importURL, appName) = importURL(for: client, listURL: listURL, ruleName: rule.displayName) {
            if UIApplication.shared.canOpenURL(importURL) {
                UIApplication.shared.open(importURL, options: [:], completionHandler: nil)
                return "正在打开\(appName)导入…"
            }
            return Clipboard.copy(listURL.absoluteString) ? "已复制链接，请手动导入" : "复制失败，请重试"
        }
        return Clipboard.copy(listURL.absoluteString) ? "已复制链接，请手动导入" : "复制失败，请重试"
    }
}

/// 首页：只用来选代理工具。点进一个客户端后进入二级页查看/搜索规则。
struct ContentView: View {
    @StateObject private var store = MagicRuleStore()
    @State private var toast: String?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brandRow
                    overviewStats
                    clientGrid
                    if let notice = store.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 20)
                    }
                    if store.isOffline {
                        Label("当前离线：显示缓存或内置数据", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
                .padding(.top, 6)
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable {
                await store.refresh(force: true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { client in
                ClientRulesView(client: client, store: store, onToast: { toast = $0 })
            }
            .task {
                await store.refreshIfNeeded()
            }
        }
        // Toast 挂在 NavigationStack 这一层，二级页/详情页里也能看到。
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toast)
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            toast = nil
        }
    }

    // MARK: - 品牌行

    private var brandRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.amberGradient)
                    .frame(width: 36, height: 36)
                Image(systemName: "cube.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 0) {
                Text("Magic")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Rule")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if store.isLoading {
                ProgressView()
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            } else {
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新数据")
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 总览统计

    private var overviewStats: some View {
        HStack(spacing: 12) {
            // 摘要还在后台加载时显示占位，解完立刻填数。
            StatCard(value: store.summaries.isEmpty ? "…" : CountFormat.plain(store.totalRuleCount), label: "规则", accent: false)
            StatCard(value: "\(MagicRuleClient.all.count)", label: "客户端", accent: true)
            StatCard(value: store.summaries.isEmpty ? "加载中" : RelativeFormat.string(from: store.latestGeneratedAt), label: "最近更新", accent: false)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 客户端网格

    private var clientGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择客户端")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 20)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MagicRuleClient.all, id: \.self) { client in
                    NavigationLink(value: client) {
                        ClientCard(
                            client: client,
                            summary: store.summary(for: client)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - 客户端卡片（首页）

private struct ClientCard: View {
    let client: String
    let summary: ClientSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ClientIconView(client: client, size: 44)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 4)
            }
            Text(client)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(summary == nil ? "加载中…" : "\(CountFormat.plain(summary!.ruleCount)) 条规则")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Text(summary == nil ? "" : "更新于 \(RelativeFormat.string(from: summary!.generatedAt))")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

// MARK: - 二级页：某客户端的规则（查看 + 搜索 + 排序）

struct ClientRulesView: View {
    let client: String
    @ObservedObject var store: MagicRuleStore
    let onToast: (String) -> Void

    @State private var query = ""
    @State private var sort: RuleSort = .updated
    @FocusState private var searchFocused: Bool

    private var allRules: [MagicRule] {
        store.rules(for: client)
    }

    private var results: [MagicRule] {
        sort.sort(store.search(query, scope: client))
    }

    private var distinctTypeCount: Int {
        Set(allRules.flatMap { $0.types }).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clientHeader
                statCards
                searchBar
                sortControl
                resultList
            }
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable {
            await store.refresh(force: true)
        }
        .navigationTitle(client)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MagicRule.self) { rule in
            RuleDetailView(rule: rule, client: client, onToast: onToast)
        }
        .task {
            // 懒加载：点进二级页时才在后台解码该客户端的完整规则列表。
            await store.ensureRulesLoaded(for: client)
        }
    }

    // MARK: - 客户端头

    private var clientHeader: some View {
        HStack(spacing: 14) {
            ClientIconView(client: client, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(client)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("客户端 · \(CountFormat.plain(store.summary(for: client)?.ruleCount ?? allRules.count)) 条规则")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 统计卡

    private var statCards: some View {
        HStack(spacing: 12) {
            StatCard(value: CountFormat.plain(store.summary(for: client)?.ruleCount ?? allRules.count), label: "规则", accent: false)
            StatCard(value: store.isClientLoaded(client) ? "\(distinctTypeCount)" : "…", label: "规则类型", accent: true)
            StatCard(value: RelativeFormat.string(from: store.generatedAt(for: client)), label: "最近更新", accent: false)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
            TextField("搜索规则名或中文名，例如：抖音、去广告", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Theme.card, in: Capsule())
        .overlay {
            Capsule()
                .stroke(searchFocused ? Theme.accent.opacity(0.6) : Theme.cardStroke, lineWidth: searchFocused ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: searchFocused)
    }

    // MARK: - 排序

    private var sortControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Picker("排序", selection: $sort) {
                ForEach(RuleSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 规则列表

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(query.isEmpty ? "全部规则" : "搜索结果")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("\(results.count) 条")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)

            if !store.isClientLoaded(client) && allRules.isEmpty {
                // 懒加载中：完整规则还在后台解码，先显示加载态，不堵界面。
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在加载规则…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else if results.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentSoft)
                            .frame(width: 88, height: 88)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("没有找到相关规则")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("换个关键词试试")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(results) { rule in
                        NavigationLink(value: rule) {
                            RuleRowCard(rule: rule, client: client)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - 统计卡

private struct StatCard: View {
    let value: String
    let label: String
    let accent: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(accent ? Theme.accent : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

// MARK: - 规则卡片

private struct RuleRowCard: View {
    let rule: MagicRule
    let client: String?

    var body: some View {
        HStack(spacing: 14) {
            RuleIconView(urlString: rule.iconURL, size: 52, label: rule.displayName)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(rule.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if rule.hasSeparateChineseName {
                        Text(rule.name)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                if let desc = rule.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(rule.types.prefix(2), id: \.self) { type in
                        TypeBadge(text: type)
                    }
                    CountPill(text: "共 \(CountFormat.plain(rule.totalLineCount)) 条")
                    Text(DateFormat.short(rule.updatedDate))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 28, height: 28)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

// MARK: - 客户端图标（打包进 Bundle 的真实图标，离线可用）
//
// 图标来源：MagicRule 网页版前端的静态资源 `https://magicrule.pages.dev/logos/<小写客户端名>.png`
//（网页版 JS 里就是 `./logos/${name.toLowerCase()}.png`），11 个已全部下载进 Bundle
//（Anywhere 原图 1024px/1MB 已压到 512px）。加载一次后进内存缓存；App 启动时在后台预热，
// 首屏渲染不卡。找不到图标时回退到首字母瓦片，不空白。
enum ClientIcon {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func image(for client: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let img = cache[client] { return img }
        guard let url = Bundle.main.url(forResource: client, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache[client] = img
        return img
    }

    /// 后台预热：把 11 个客户端图标先解码进缓存。
    static func prewarm() {
        for client in MagicRuleClient.all {
            _ = image(for: client)
        }
    }
}

struct ClientIconView: View {
    let client: String
    let size: CGFloat

    var body: some View {
        Group {
            if let uiImage = ClientIcon.image(for: client) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.27)
                        .fill(Theme.accentSoft)
                    Text(String(client.prefix(1)))
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
    }
}

// MARK: - 规则图标（异步加载 + 磁盘缓存，失败时显示名字首字占位）

struct RuleIconView: View {
    let urlString: String?
    let size: CGFloat
    var label: String? = nil

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(Theme.accentSoft)
            if let label, let first = label.first {
                Text(String(first))
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - 详情页

struct RuleDetailView: View {
    let rule: MagicRule
    let client: String
    let onToast: (String) -> Void

    @State private var isImporting = false

    private var manifestURL: URL? {
        guard let m = rule.manifest else { return nil }
        return URL(string: m)
    }

    private var shareURL: URL? {
        RuleImport.shareURL(for: rule)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区
                HStack(spacing: 16) {
                    RuleIconView(urlString: rule.iconURL, size: 72, label: rule.displayName)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.displayName)
                            .font(.title2.bold())
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        if rule.hasSeparateChineseName {
                            Text(rule.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                        HStack(spacing: 6) {
                            ForEach(rule.types, id: \.self) { type in
                                TypeBadge(text: type)
                            }
                        }
                    }
                    Spacer()
                }

                // 描述
                if let desc = rule.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("简介")
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                }

                // 统计
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("统计")
                    HStack(spacing: 12) {
                        StatBox(title: "总行数", value: CountFormat.plain(rule.totalLineCount), icon: "list.number")
                        StatBox(title: "规则类型", value: "\(rule.types.count) 种", icon: "tag")
                        StatBox(title: "上游来源", value: "\(rule.providers.count) 个", icon: "link")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rule.sortedTypeCounts, id: \.key) { item in
                            TypeCountRow(
                                type: item.key,
                                count: item.value,
                                fraction: rule.totalLineCount > 0
                                    ? Double(item.value) / Double(rule.totalLineCount) : 0
                            )
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("规则更新于 \(DateFormat.full(rule.updatedDate))")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.secondary)
                }

                // 操作：复制链接 + 一键导入
                HStack(spacing: 12) {
                    Button {
                        if let url = shareURL {
                            onToast(Clipboard.copy(url.absoluteString) ? "链接已复制" : "复制失败，请重试")
                        }
                    } label: {
                        Label("复制规则链接", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.amberGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .font(.body.weight(.semibold))
                    .disabled(shareURL == nil)

                    Button {
                        guard !isImporting else { return }
                        isImporting = true
                        Task {
                            let message = await RuleImport.attemptImport(client: client, rule: rule)
                            onToast(message)
                            isImporting = false
                        }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .frame(minHeight: 48)
                                .padding(.horizontal, 16)
                        } else {
                            Label("一键导入", systemImage: "square.and.arrow.down")
                                .frame(minHeight: 48)
                                .padding(.horizontal, 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.accent)
                    .font(.body.weight(.semibold))
                    .disabled(shareURL == nil)
                }
                if !RuleImport.supportsImport(client: client) {
                    Text("当前客户端暂不支持一键导入，点击将复制规则链接，请在 \(client) 内手动添加。")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }

                // manifest
                if let manifestURL {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Manifest")
                        LinkRow(title: "manifest.json", url: manifestURL, onToast: onToast)
                    }
                }

                // 上游 provider
                if !rule.providers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("上游来源（\(rule.providers.count)）")
                        VStack(spacing: 8) {
                            ForEach(rule.providers, id: \.self) { provider in
                                if let url = URL(string: provider) {
                                    LinkRow(title: provider, url: url, onToast: onToast)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(rule.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 小组件

private struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 4, height: 16)
            Text(text)
                .font(.headline)
                .foregroundStyle(Theme.text)
        }
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct TypeCountRow: View {
    let type: String
    let count: Int
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(type)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(CountFormat.plain(count))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(6, geo.size.width * fraction), height: 6)
                    }
            }
            .frame(height: 6)
        }
    }
}

private struct LinkRow: View {
    let title: String
    let url: URL
    let onToast: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: url) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Button {
                onToast(Clipboard.copy(url.absoluteString) ? "链接已复制" : "复制失败，请重试")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制链接")
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

/// 类型徽标：米色药丸 + 等宽字体（对齐 MagicRule 网页版）。
private struct TypeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.badgeBg, in: Capsule())
            .foregroundStyle(Theme.badgeText)
    }
}

/// “共 X 条”琥珀药丸。
private struct CountPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accentSoft, in: Capsule())
            .foregroundStyle(Theme.accent)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
