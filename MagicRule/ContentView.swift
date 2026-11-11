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

/// 首页：品牌行 + 客户端头 + 统计卡 + 客户端切换 + 搜索 + 规则列表。
struct ContentView: View {
    @StateObject private var store = MagicRuleStore()
    @State private var selectedClient: String? = "QuantumultX"
    @State private var query = ""
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    private var results: [MagicRule] {
        store.search(query, scope: selectedClient)
    }

    /// 当前选中客户端（或全部）的全部规则（不受搜索过滤）。
    private var currentRules: [MagicRule] {
        if let selectedClient {
            return store.rules(for: selectedClient)
        }
        return MagicRuleClient.all.flatMap { store.rules(for: $0) }
    }

    private var distinctTypeCount: Int {
        Set(currentRules.flatMap { $0.types }).count
    }

    private var latestUpdate: Date? {
        if let selectedClient {
            return store.generatedAt(for: selectedClient)
        }
        return store.latestGeneratedAt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brandRow
                    clientHeader
                    statCards
                    clientPicker
                    searchBar
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
                    resultList
                }
                .padding(.bottom, 24)
                .padding(.top, 6)
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable {
                await store.refresh(force: true)
            }
            .toolbar(.hidden, for: .navigationBar)
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
                try? await Task.sleep(for: .seconds(2.2))
                toast = nil
            }
            .task {
                await store.refreshIfNeeded()
            }
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

    // MARK: - 客户端头

    private var clientHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.accentSoft)
                    .frame(width: 56, height: 56)
                if let client = selectedClient {
                    Text(String(client.prefix(1)))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedClient ?? "全部规则")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(selectedClient == nil
                     ? "11 个客户端 · \(CountFormat.plain(store.totalRuleCount)) 条规则"
                     : "客户端 · \(CountFormat.plain(currentRules.count)) 条规则")
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
            StatCard(value: CountFormat.plain(currentRules.count), label: "规则", accent: false)
            StatCard(value: "\(distinctTypeCount)", label: "规则类型", accent: true)
            StatCard(value: RelativeFormat.string(from: latestUpdate), label: "最近更新", accent: false)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 客户端选择器

    private var clientPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                clientPill(title: "全部", count: store.totalRuleCount, selected: selectedClient == nil) {
                    selectedClient = nil
                }
                ForEach(MagicRuleClient.all, id: \.self) { client in
                    clientPill(
                        title: client,
                        count: store.rules(for: client).count,
                        selected: selectedClient == client
                    ) {
                        selectedClient = client
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func clientPill(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selected ? Color.white.opacity(0.25) : Theme.badgeBg, in: Capsule())
                    .foregroundStyle(selected ? .white : Theme.badgeText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? .white : Theme.text)
            .background {
                if selected {
                    Capsule().fill(Theme.amberGradient)
                } else {
                    Capsule().fill(Theme.card).stroke(Theme.cardStroke, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.14 : 0.04), radius: selected ? 8 : 5, y: 2)
        }
        .buttonStyle(.plain)
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
                if selectedClient == nil {
                    Text("跨客户端")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 20)

            if results.isEmpty {
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
                            RuleRowCard(rule: rule, client: selectedClient)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationDestination(for: MagicRule.self) { rule in
            RuleDetailView(rule: rule, onToast: { toast = $0 })
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
            RuleIconView(urlString: rule.iconURL, size: 52)
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

// MARK: - 规则图标（异步加载，失败回退 SF Symbol）

struct RuleIconView: View {
    let urlString: String?
    let size: CGFloat

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
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accentSoft)
            Image(systemName: "globe")
                .font(.body)
                .foregroundStyle(Theme.accent)
        }
    }
}

// MARK: - 详情页

struct RuleDetailView: View {
    let rule: MagicRule
    let onToast: (String) -> Void

    private var manifestURL: URL? {
        guard let m = rule.manifest else { return nil }
        return URL(string: m)
    }

    private var shareURL: URL? {
        manifestURL ?? rule.providers.compactMap { URL(string: $0) }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区
                HStack(spacing: 16) {
                    RuleIconView(urlString: rule.iconURL, size: 72)
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

                // 操作
                HStack(spacing: 12) {
                    Button {
                        if let url = shareURL {
                            UIPasteboard.general.string = url.absoluteString
                            onToast("链接已复制")
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

                    if let url = shareURL {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(minHeight: 48)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.accent)
                        .font(.body.weight(.semibold))
                    }
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
                UIPasteboard.general.string = url.absoluteString
                onToast("链接已复制")
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
