import Foundation
import Network

/// 数据层：内置索引 → Worker 最新数据 → 本地文件缓存，三级兜底。
///
/// - 内置：打包进 App Bundle 的 11 个 `index/<Client>.json`，开箱即用。
/// - Worker：`https://magicrule-crawler.8868.workers.dev/data/index/<Client>.json`，
///   打开时自动拉一次，也支持下拉手动刷新；拉到的 JSON 写文件缓存。
/// - 缓存：没网时用缓存，缓存也没有时用内置数据。
@MainActor
final class MagicRuleStore: ObservableObject {
    enum Source: Equatable {
        case bundled
        case cache
        case worker
    }

    nonisolated static let workerBase = "https://magicrule-crawler.8868.workers.dev"

    /// 缓存版本号。升级 App 时旧版本缓存一律丢弃（build 4 的缓存里中文名/icon 是被污染的旧数据，
    /// Caches 目录跨版本保留，不加版本控制会一直盖住正确的内置数据，导致中文搜索和图标持续出错）。
    /// 每次缓存格式或数据语义变化时把这个数字加 1。
    nonisolated static let cacheVersion = 2

    @Published private(set) var rulesByClient: [String: [MagicRule]] = [:]
    @Published private(set) var generatedAtByClient: [String: Date] = [:]
    @Published private(set) var source: Source = .bundled
    @Published private(set) var isLoading = false
    @Published private(set) var isOffline = false
    @Published var notice: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "magicrule.network")
    private var hasRefreshed = false

    private nonisolated static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    init() {
        loadBundled()
        loadCache()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 派生状态

    var totalRuleCount: Int {
        rulesByClient.values.reduce(0) { $0 + $1.count }
    }

    func rules(for client: String) -> [MagicRule] {
        rulesByClient[client] ?? []
    }

    /// 最新一条索引的生成时间（各客户端取最大）。
    var latestGeneratedAt: Date? {
        generatedAtByClient.values.max()
    }

    /// 某个客户端索引的生成时间。
    func generatedAt(for client: String) -> Date? {
        generatedAtByClient[client]
    }

    var sourceText: String {
        switch source {
        case .bundled: return "内置数据"
        case .cache: return "本地缓存"
        case .worker: return "Worker 最新数据"
        }
    }

    var updatedText: String {
        if let date = latestGeneratedAt {
            return "\(sourceText) · 更新于 \(DateFormat.full(date))"
        }
        return sourceText
    }

    // MARK: - 内置数据

    private func loadBundled() {
        for client in MagicRuleClient.all {
            guard let url = Bundle.main.url(forResource: client, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let index = try? Self.decoder.decode(ClientIndex.self, from: data) else {
                continue
            }
            rulesByClient[client] = index.rules
            if let date = MagicRule.date(from: index.generatedAt) {
                generatedAtByClient[client] = date
            }
        }
        source = .bundled
    }

    // MARK: - 文件缓存

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicRuleIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheURL(for client: String) -> URL {
        cacheDirectory.appendingPathComponent("\(client).json")
    }

    private var cacheVersionURL: URL {
        cacheDirectory.appendingPathComponent("version")
    }

    /// 丢弃全部本地缓存（版本不对时调用，也用于旧版本升级）。
    private func discardCache() {
        let fm = FileManager.default
        for client in MagicRuleClient.all {
            try? fm.removeItem(at: cacheURL(for: client))
        }
        try? fm.removeItem(at: cacheVersionURL)
    }

    private func loadCache() {
        // 版本校验：没有版本号文件、或版本号对不上，一律丢弃缓存，只用内置数据，
        // 再由 refresh() 从 Worker 拉最新数据并按新版本重写缓存。
        // 这样从 build 4 / build 6 升级上来的旧缓存一定被丢弃，不会再盖住正确数据。
        let version = try? String(contentsOf: cacheVersionURL, encoding: .utf8)
        guard version?.trimmingCharacters(in: .whitespacesAndNewlines) == "\(Self.cacheVersion)" else {
            discardCache()
            return
        }
        var loadedAny = false
        for client in MagicRuleClient.all {
            let url = cacheURL(for: client)
            guard let data = try? Data(contentsOf: url),
                  let index = try? Self.decoder.decode(ClientIndex.self, from: data) else {
                continue
            }
            rulesByClient[client] = index.rules
            if let date = MagicRule.date(from: index.generatedAt) {
                generatedAtByClient[client] = date
            }
            loadedAny = true
        }
        if loadedAny { source = .cache }
    }

    private func saveCache(client: String, data: Data) {
        try? data.write(to: cacheURL(for: client), options: .atomic)
        try? "\(Self.cacheVersion)".write(to: cacheVersionURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Worker 刷新

    /// 打开时自动拉一次（只拉一次）；下拉刷新走 refresh(force:)。
    func refreshIfNeeded() async {
        guard !hasRefreshed else { return }
        hasRefreshed = true
        await refresh(force: false)
    }

    func refresh(force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        notice = nil
        defer { isLoading = false }

        var fetched: [String: ClientIndex] = [:]
        await withTaskGroup(of: (String, ClientIndex?).self) { group in
            for client in MagicRuleClient.all {
                group.addTask {
                    let url = URL(string: "\(Self.workerBase)/data/index/\(client).json")!
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 20
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            return (client, nil)
                        }
                        let index = try Self.decoder.decode(ClientIndex.self, from: data)
                        return (client, index)
                    } catch {
                        return (client, nil)
                    }
                }
            }
            for await (client, index) in group {
                if let index { fetched[client] = index }
            }
        }

        if fetched.isEmpty {
            // 全部失败：保持现有数据（缓存或内置），只提示。
            if isOffline {
                notice = "当前离线，显示的是\(sourceText)。"
            } else {
                notice = "拉取最新数据失败，显示的是\(sourceText)；下拉可重试。"
            }
            return
        }

        // 部分成功也更新成功的客户端，并写缓存。
        for (client, index) in fetched {
            rulesByClient[client] = index.rules
            if let date = MagicRule.date(from: index.generatedAt) {
                generatedAtByClient[client] = date
            }
            if let data = try? JSONEncoder().encode(index) {
                saveCache(client: client, data: data)
            }
        }
        source = .worker
        if fetched.count < MagicRuleClient.all.count {
            notice = "已更新 \(fetched.count)/\(MagicRuleClient.all.count) 个客户端，其余仍用旧数据。"
        }
    }

    // MARK: - 搜索

    /// 按名字 / 中文名搜索；scope 为 nil 时搜全部客户端。
    func search(_ query: String, scope: String?) -> [MagicRule] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool: [MagicRule]
        if let scope {
            pool = rulesByClient[scope] ?? []
        } else {
            pool = MagicRuleClient.all.flatMap { rulesByClient[$0] ?? [] }
        }
        guard !q.isEmpty else { return pool }
        return pool.filter { rule in
            rule.name.lowercased().contains(q)
                || (rule.chineseName?.lowercased().contains(q) ?? false)
                || rule.displayName.lowercased().contains(q)
        }
    }
}
