import SwiftUI
import UIKit

/// 首页：客户端切换 + 搜索 + 规则列表。
/// 设计：渐变头图、横向滚动客户端药丸、圆角卡片、语义色，亮暗模式都好看。
struct ContentView: View {
    @StateObject private var store = MagicRuleStore()
    @State private var selectedClient: String? = "QuantumultX"
    @State private var query = ""
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    private var results: [MagicRule] {
        store.search(query, scope: selectedClient)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    clientPicker
                    searchBar
                    if let notice = store.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    if store.isOffline {
                        Label("当前离线：显示缓存或内置数据", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 20)
                    }
                    resultList
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await store.refresh(force: true)
            }
            .navigationTitle("MagicRule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                    .accessibilityLabel("刷新数据")
                }
            }
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

    // MARK: - 头图

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.22))
                        .frame(width: 52, height: 52)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("规则索引浏览器")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("11 个客户端 · \(CountFormat.plain(store.totalRuleCount)) 条规则")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                Text(store.updatedText)
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.purple, Color.pink.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: .indigo.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
                    .background(
                        (selected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15)),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                selected ? Color.accentColor : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .foregroundStyle(selected ? .white : .primary)
            .shadow(color: .black.opacity(selected ? 0.12 : 0.03), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(searchFocused ? 0.5 : 0), lineWidth: 2)
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: searchFocused)
    }

    // MARK: - 规则列表

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(query.isEmpty ? "全部规则" : "搜索结果")
                    .font(.headline)
                Text("\(results.count) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedClient == nil {
                    Text("跨客户端")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.tertiary)
                    Text("没有找到相关规则")
                        .font(.headline)
                    Text("换个关键词试试")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

// MARK: - 规则卡片

private struct RuleRowCard: View {
    let rule: MagicRule
    let client: String?

    var body: some View {
        HStack(spacing: 14) {
            RuleIconView(urlString: rule.iconURL, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(rule.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if rule.hasSeparateChineseName {
                        Text(rule.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let desc = rule.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(rule.types.prefix(2), id: \.self) { type in
                        Badge(text: type, tint: .indigo)
                    }
                    Text(CountFormat.lines(rule.totalLineCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(DateFormat.short(rule.updatedDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
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
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.indigo.opacity(0.14))
            Image(systemName: "globe")
                .font(.body)
                .foregroundStyle(.indigo)
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
                            .lineLimit(2)
                        if rule.hasSeparateChineseName {
                            Text(rule.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            ForEach(rule.types, id: \.self) { type in
                                Badge(text: type, tint: .indigo)
                            }
                        }
                    }
                    Spacer()
                }

                // 描述
                if let desc = rule.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("简介")
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                // 统计
                VStack(alignment: .leading, spacing: 8) {
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
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("规则更新于 \(DateFormat.full(rule.updatedDate))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
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
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13))
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
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(Color.accentColor)
                        .font(.body.weight(.semibold))
                    }
                }

                // manifest
                if let manifestURL {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Manifest")
                        LinkRow(title: "manifest.json", url: manifestURL, onToast: onToast)
                    }
                }

                // 上游 provider
                if !rule.providers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
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
        .background(Color(.systemGroupedBackground))
        .navigationTitle(rule.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 小组件

private struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
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
                .foregroundStyle(.indigo)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
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
                Spacer()
                Text(CountFormat.plain(count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Color.indigo.opacity(0.18))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.indigo)
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
                        .foregroundStyle(.indigo)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Button {
                UIPasteboard.general.string = url.absoluteString
                onToast("链接已复制")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制链接")
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
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
