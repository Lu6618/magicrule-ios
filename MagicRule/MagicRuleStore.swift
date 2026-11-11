import Foundation
import Network

/// 数据层：内置索引 → Worker 最新数据 → 本地文件缓存，三级兜底。
///
/// - 内置：打包进 App Bundle 的 11 个 `index/<Client>.json`，开箱即用。
/// - Worker：`https://magicrule-crawler.8868.workers.dev/data/index/<Client>.json`，
///   打开时自动拉一次，也支持下拉手动刷新；拉到的 JSON 写文件缓存。
/// - 缓存：没网时用缓存，缓存也没有时用内置数据。
///
/// 性能设计（build 9，解决启动卡顿）：
/// - 启动时只在后台解各客户端的轻量摘要（名字、规则条数、最近更新时间），
///   首页立刻出现；完整规则列表按客户端懒加载，点进二级页时才在后台解码。
/// - 所有 JSON 解码都在后台线程（Task.detached / 非隔离静态方法），
///   @MainActor 的 Store 只持有结果、驱动界面，主线程不做解码。
/// - Worker 拉回来的 JSON 解码、写缓存的编码也都在后台做。
///
/// 性能设计（build 11，解决二级页卡顿）：
/// - 摘要加载完后立即在后台低优先级预加载全部 11 个客户端的完整规则
///   （逐个解码，.utility 优先级，不抢主线程和首页交互），
///   用户点进二级页时数据大多已在内存里，直接出列表，不用等解码。
/// - 预加载与懒加载共享同一份在途解码任务（inFlightLoads），
///   同一客户端只解一次：用户在预加载完成前点进去，等正在解的任务完成即可。
/// - Worker 刷新成功时会覆盖为最新数据，预加载的结果不会盖住它。
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

    /// 各客户端轻量摘要（首页用）。启动时后台加载，首页先出骨架再填数。
    @Published private(set) var summaries: [String: ClientSummary] = [:]
    /// 完整规则列表（按客户端懒加载）。
    @Published private(set) var rulesByClient: [String: [MagicRule]] = [:]
    @Published private(set) var source: Source = .bundled
    @Published private(set) var isLoading = false
    @Published private(set) var isOffline = false
    @Published var notice: String?
    /// 已完成完整规则加载的客户端。
    @Published private(set) var loadedClients: Set<String> = []
    /// 正在后台解码完整规则的客户端（二级页显示加载中）。
    @Published private(set) var loadingClients: Set<String> = []
    /// 启动进度（启动动画用）：0→1，跟真实加载挂钩。
    /// 摘要就绪 0.1；之后每完成一个客户端的完整规则加载 +0.9/11；加载失败也计入，不会卡住。
    @Published private(set) var launchProgress: Double = 0
    /// 启动期已尝试加载完整规则的客户端数（成功或失败都算）。
    @Published private(set) var launchLoadedCount = 0
    /// 全部启动数据就绪（可进入首页）。
    @Published private(set) var isLaunchReady = false
    /// 在途解码任务（预加载与懒加载共享，同一客户端只解一次）。
    /// key 是客户端名，value 是后台解码该客户端完整索引的任务。
    private var inFlightLoads: [String: Task<ClientIndex?, Never>] = [:]
    /// 后台预加载任务（同一时间只跑一个；跑完置 nil，下拉刷新后可再跑一次补缺口）。
    private var preloadTask: Task<Void, Never>?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "magicrule.network")
    private var hasRefreshed = false

    private nonisolated static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: monitorQueue)
        // 启动不堵界面：启动序列在后台加载全部数据（摘要 + 11 个客户端完整规则），
        // 进度实时发布，启动页显示进度条；到 100% 再进首页。
        Task { await runLaunchSequence() }
    }

    // MARK: - 派生状态

    var totalRuleCount: Int {
        summaries.values.reduce(0) { $0 + $1.ruleCount }
    }

    func summary(for client: String) -> ClientSummary? {
        summaries[client]
    }

    func rules(for client: String) -> [MagicRule] {
        rulesByClient[client] ?? []
    }

    /// 该客户端的完整规则是否已加载进内存。
    func isClientLoaded(_ client: String) -> Bool {
        loadedClients.contains(client)
    }

    /// 该客户端的完整规则是否正在后台解码。
    func isClientLoading(_ client: String) -> Bool {
        loadingClients.contains(client)
    }

    /// 最新一条索引的生成时间（各客户端取最大）。
    var latestGeneratedAt: Date? {
        summaries.values.compactMap { $0.generatedAt }.max()
    }

    /// 某个客户端索引的生成时间。
    func generatedAt(for client: String) -> Date? {
        summaries[client]?.generatedAt
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

    /// 启动页状态文案：摘要阶段 / 正在加载规则 x/11 / 加载完成。
    var launchStatusText: String {
        if launchProgress < 0.1 { return "正在加载摘要…" }
        if launchLoadedCount < MagicRuleClient.all.count {
            return "正在加载规则… \(launchLoadedCount)/\(MagicRuleClient.all.count)"
        }
        return "加载完成"
    }

    // MARK: - 启动：后台加载全部数据，进度真实挂钩（build 15）

    /// 启动序列：摘要（0→0.1）→ 11 个客户端完整规则（0.1→1.0，每完成一个 +0.9/11，
    /// 失败也计入，不会卡在 99%）→ 进度到 100% 进入首页；Worker 刷新在进入首页后
    /// 后台继续跑，不堵启动。全部解码在后台线程，主线程只发布进度。
    private func runLaunchSequence() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            await Self.loadSummariesFromDisk()
        }.value
        summaries = loaded.summaries
        source = loaded.source
        launchProgress = 0.1
        for client in MagicRuleClient.all {
            await preloadOne(client)
            launchLoadedCount += 1
            launchProgress = 0.1 + 0.9 * Double(launchLoadedCount) / Double(MagicRuleClient.all.count)
        }
        launchProgress = 1.0
        isLaunchReady = true
        // 进入首页后，后台拉 Worker 最新数据（不堵启动）。
        await refreshIfNeeded()
    }

    // MARK: - 按客户端懒加载完整规则 + 后台预加载（build 11）

    /// 进入某客户端二级页时调用：后台解码该客户端的完整规则列表。
    /// 已加载过直接返回；预加载正在解这个客户端时，等它解完即可，不重复解码；
    /// 否则以 .userInitiated 优先级在后台解码（用户正在等，优先级高于预加载）。
    func ensureRulesLoaded(for client: String) async {
        if loadedClients.contains(client) { return }
        if let existing = inFlightLoads[client] {
            await finishLoad(for: client, task: existing)
            return
        }
        loadingClients.insert(client)
        let task = Task.detached(priority: .userInitiated) {
            Self.loadFullIndex(for: client)
        }
        inFlightLoads[client] = task
        await finishLoad(for: client, task: task)
    }

    /// 启动后台预加载（只同时跑一个；跑完置 nil，之后下拉刷新可再触发一次补缺口）。
    /// 触发时机：摘要加载完后（与 Worker 刷新并行）、每次刷新结束时。
    /// 低优先级（.background 循环 + .utility 解码）、逐个客户端顺序解，
    /// 不抢主线程和首页交互；全部解完约几秒，用户一般还没点进二级页。
    private func startPreloadIfNeeded() {
        guard preloadTask == nil else { return }
        preloadTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            for client in MagicRuleClient.all {
                if Task.isCancelled { break }
                await self.preloadOne(client)
            }
            self.preloadTask = nil
        }
    }

    /// 预加载某一个客户端：已加载的跳过；在途的等它解完；否则低优先级新起解码任务。
    private func preloadOne(_ client: String) async {
        if loadedClients.contains(client) { return }
        if let existing = inFlightLoads[client] {
            await finishLoad(for: client, task: existing)
            return
        }
        let task = Task.detached(priority: .utility) {
            Self.loadFullIndex(for: client)
        }
        inFlightLoads[client] = task
        await finishLoad(for: client, task: task)
    }

    /// 等一个解码任务完成并把结果发布到主线程。
    /// 两个调用方可能同时等同一个任务：先完成的发布，后完成的看到
    /// loadedClients 已包含该客户端就跳过，不会重复发布，也不会盖掉
    /// Worker 刷新期间已发布的新数据。
    private func finishLoad(for client: String, task: Task<ClientIndex?, Never>) async {
        let index = await task.value
        inFlightLoads[client] = nil
        loadingClients.remove(client)
        guard !loadedClients.contains(client), let index else { return }
        rulesByClient[client] = index.rules
        let date = MagicRule.date(from: index.generatedAt)
        summaries[client] = ClientSummary(
            client: client,
            ruleCount: index.rules.count,
            generatedAt: date ?? summaries[client]?.generatedAt
        )
        loadedClients.insert(client)
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
        // 刷新结束（无论成功、部分成功还是全部失败）都触发一次预加载补缺口：
        // 刷新没拉到的客户端由预加载从内置/缓存解码进内存，二级页点进去直接出列表。
        defer { startPreloadIfNeeded() }

        // 1. 并行拉取（纯网络 I/O，不解码）。
        let fetchedData: [(String, Data)] = await withTaskGroup(of: (String, Data?).self) { group in
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
                        return (client, data)
                    } catch {
                        return (client, nil)
                    }
                }
            }
            var out: [(String, Data)] = []
            for await (client, data) in group {
                if let data { out.append((client, data)) }
            }
            return out
        }

        if fetchedData.isEmpty {
            // 全部失败：保持现有数据（缓存或内置），只提示。
            if isOffline {
                notice = "当前离线，显示的是\(sourceText)。"
            } else {
                notice = "拉取最新数据失败，显示的是\(sourceText)；下拉可重试。"
            }
            return
        }

        // 2. 后台解码 + 写缓存（编码也在后台做，不堵主线程）。
        let decoded = await Task.detached(priority: .userInitiated) {
            var result: [(String, ClientIndex)] = []
            for (client, data) in fetchedData {
                guard let index = Self.decodeIndex(from: data) else { continue }
                result.append((client, index))
                if let encoded = try? JSONEncoder().encode(index) {
                    Self.saveCacheData(client: client, data: encoded)
                }
            }
            return result
        }.value

        // 3. 回主线程发布。
        for (client, index) in decoded {
            rulesByClient[client] = index.rules
            let date = MagicRule.date(from: index.generatedAt)
            summaries[client] = ClientSummary(
                client: client,
                ruleCount: index.rules.count,
                generatedAt: date ?? summaries[client]?.generatedAt
            )
            loadedClients.insert(client)
        }
        source = .worker
        if decoded.count < MagicRuleClient.all.count {
            notice = "已更新 \(decoded.count)/\(MagicRuleClient.all.count) 个客户端，其余仍用旧数据。"
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

    // MARK: - 后台解码（非隔离静态方法，不碰主线程）

    /// 轻量摘要解码：只读 generated_at 和 rules 条数，不解码每条规则的内容。
    /// 用 JSONSerialization 只解析顶层结构，比 Codable 全量解码轻得多。
    /// 注意缓存文件是 Codable 编码的驼峰 key（generatedAt），内置文件是蛇形 key（generated_at），两种都认。
    nonisolated static func decodeSummary(client: String, from data: Data) -> ClientSummary? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let count = (obj["rules"] as? [Any])?.count ?? 0
        let generatedAtString = (obj["generated_at"] as? String) ?? (obj["generatedAt"] as? String)
        return ClientSummary(
            client: client,
            ruleCount: count,
            generatedAt: MagicRule.date(from: generatedAtString)
        )
    }

    /// 完整索引解码（Codable 全量，11,841 条规则，约 12 个字段/条）。
    nonisolated static func decodeIndex(from data: Data) -> ClientIndex? {
        try? decoder.decode(ClientIndex.self, from: data)
    }

    /// 后台：读内置 + 缓存，解出各客户端摘要。返回（摘要，来源）。
    /// 先读内置（来源 .bundled），再读缓存覆盖（版本有效时来源变 .cache）。
    nonisolated static func loadSummariesFromDisk() async -> (summaries: [String: ClientSummary], source: Source) {
        var summaries: [String: ClientSummary] = [:]
        // 内置摘要：并行解。
        await withTaskGroup(of: (String, ClientSummary?).self) { group in
            for client in MagicRuleClient.all {
                group.addTask {
                    guard let url = Bundle.main.url(forResource: client, withExtension: "json"),
                          let data = try? Data(contentsOf: url) else {
                        return (client, nil)
                    }
                    return (client, decodeSummary(client: client, from: data))
                }
            }
            for await (client, summary) in group {
                if let summary { summaries[client] = summary }
            }
        }
        var source: Source = .bundled
        // 缓存摘要（版本校验）。
        if cacheVersionIsValid() {
            var loadedAny = false
            await withTaskGroup(of: (String, ClientSummary?).self) { group in
                for client in MagicRuleClient.all {
                    group.addTask {
                        guard let data = try? Data(contentsOf: cacheURL(for: client)) else {
                            return (client, nil)
                        }
                        return (client, decodeSummary(client: client, from: data))
                    }
                }
                for await (client, summary) in group {
                    if let summary {
                        summaries[client] = summary
                        loadedAny = true
                    }
                }
            }
            if loadedAny { source = .cache }
        } else {
            discardCacheFiles()
        }
        return (summaries, source)
    }

    /// 后台：读某客户端的完整索引。优先缓存（版本有效时），否则内置。
    nonisolated static func loadFullIndex(for client: String) -> ClientIndex? {
        if cacheVersionIsValid(),
           let data = try? Data(contentsOf: cacheURL(for: client)),
           let index = decodeIndex(from: data) {
            return index
        }
        guard let url = Bundle.main.url(forResource: client, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decodeIndex(from: data)
    }

    // MARK: - 文件缓存（静态方法，可在后台线程调用）

    nonisolated static func cacheDirectoryURL() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicRuleIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func cacheURL(for client: String) -> URL {
        cacheDirectoryURL().appendingPathComponent("\(client).json")
    }

    nonisolated static func cacheVersionURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("version")
    }

    nonisolated static func cacheVersionIsValid() -> Bool {
        let version = try? String(contentsOf: cacheVersionURL(), encoding: .utf8)
        return version?.trimmingCharacters(in: .whitespacesAndNewlines) == "\(cacheVersion)"
    }

    /// 丢弃全部本地缓存（版本不对时调用，也用于旧版本升级）。
    nonisolated static func discardCacheFiles() {
        let fm = FileManager.default
        for client in MagicRuleClient.all {
            try? fm.removeItem(at: cacheURL(for: client))
        }
        try? fm.removeItem(at: cacheVersionURL())
    }

    nonisolated static func saveCacheData(client: String, data: Data) {
        try? data.write(to: cacheURL(for: client), options: .atomic)
        try? "\(cacheVersion)".write(to: cacheVersionURL(), atomically: true, encoding: .utf8)
    }
}
