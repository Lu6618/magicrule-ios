import SwiftUI

@main
struct MagicRuleApp: App {
    init() {
        // 图标磁盘缓存：AsyncImage 默认走 URLSession.shared，配一个带磁盘容量的
        // URLCache 后图标会落盘，重复打开不重复下载，离线也能显示。
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "MagicRuleIconCache"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
