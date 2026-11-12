import CryptoKit
import Foundation
import UIKit

/// 规则图标加载器（build 15，替代 AsyncImage；build 21 加固：更长超时、更多重试、列表页预热）。
///
/// 为什么换掉 AsyncImage（根因）：
/// - AsyncImage 的下载任务挂在视图生命周期上：列表滚动、Store 发布更新导致视图重建时，
///   在途的下载会被取消重建；本 App 启动预加载期间 Store 会连续发布 11 次更新，
///   弱网下图片可能反复被取消、一直下不完。
/// - AsyncImage 失败后不重试，失败即永久回退占位；且它走 URLSession.shared + 共享
///   URLCache，失败/异常响应一旦进了磁盘缓存会被反复命中。
/// - 图标地址和服务端都已实测正常（AbemaTV 的 mzstatic 地址 HTTP 200、image/jpeg、
///   33KB 有效 JPEG），内置数据里的 icon_url 也是对的，问题在 App 的加载环节，不在数据。
///
/// 加载器的做法：下载任务由加载器持有（不在视图上），视图重建/滚动不会取消下载；
/// 同一 URL 全 App 只下一个任务，多行共享；失败自动重试两次（共 3 次尝试）；
/// 成功后进内存（NSCache，自动回收）+ 自有磁盘缓存（不用 URLCache.shared，旧缓存里的异常
/// 响应不会再被命中）；加载中显示浅色占位（无字母），重试后仍失败才回退首字母占位。
/// 打开某客户端列表页时还会后台预热该客户端的图标（先下排前面的可见行，再往后下）。
actor RuleIconLoader {
    static let shared = RuleIconLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    private var diskDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RuleIconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileName(for urlString: String) -> String {
        SHA256.hash(data: Data(urlString.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// 取图标：内存 → 磁盘 → 网络（同 URL 只下一个任务，失败重试两次）。
    func image(for urlString: String) async -> UIImage? {
        if let img = memory.object(forKey: urlString as NSString) { return img }
        let fileURL = diskDirectory.appendingPathComponent(Self.fileName(for: urlString))
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            memory.setObject(img, forKey: urlString as NSString, cost: Self.cost(of: img))
            return img
        }
        if let task = inFlight[urlString] {
            return await task.value
        }
        let diskDir = diskDirectory
        let task = Task.detached(priority: .userInitiated) {
            await Self.download(urlString: urlString, diskDirectory: diskDir)
        }
        inFlight[urlString] = task
        let img = await task.value
        inFlight[urlString] = nil
        if let img {
            memory.setObject(img, forKey: urlString as NSString, cost: Self.cost(of: img))
        }
        return img
    }

    /// 后台预热：按传入顺序把一批图标下到磁盘缓存（低优先级调用，失败跳过，不抛错）。
    /// 调用方传默认排序后的列表即可：排前面的就是可见行，先下；再往后下。
    /// 下好的进磁盘缓存，下次打开直接读缓存，不用再等下载。
    /// 注意：只在打开某客户端列表页时预热该客户端，不要在启动时预热全部 11 个（流量太大）。
    func prewarm(urls: [String]) async {
        for urlString in urls {
            _ = await image(for: urlString)
        }
    }

    /// 显式下载：ephemeral 会话（不走 URLCache.shared），失败重试两次（共 3 次尝试）。
    /// 超时放得较宽：QX 代理下 mzstatic 可能很慢，15 秒不够。
    private static func download(urlString: String, diskDirectory: URL) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        for _ in 0..<3 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let img = UIImage(data: data) else { continue }
                try? data.write(
                    to: diskDirectory.appendingPathComponent(fileName(for: urlString)),
                    options: .atomic
                )
                return img
            } catch {
                continue
            }
        }
        return nil
    }

    /// 解码后位图大约占用的内存（宽×高×4），供 NSCache 做淘汰。
    private static func cost(of image: UIImage) -> Int {
        let size = image.size
        let scale = image.scale
        return Int(size.width * scale) * Int(size.height * scale) * 4
    }
}
