import SwiftUI

@main
struct MagicRuleApp: App {
    /// 全局唯一的 Store：启动页和首页共用，启动加载进度由它驱动。
    @StateObject private var store = MagicRuleStore()

    init() {
        // 客户端图标后台预热：11 个打包进 Bundle 的客户端图标先在后台解码进缓存，
        // 首屏渲染时直接取缓存，不在主线程解码。
        Task.detached(priority: .utility) {
            ClientIcon.prewarm()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if store.isLaunchReady {
                    ContentView(store: store)
                        .transition(.opacity)
                } else {
                    LaunchView(store: store)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.isLaunchReady)
        }
    }
}

// MARK: - 启动页（build 15）
//
// App 打开先出启动页：品牌 + 真实加载进度条，进度到 100% 再进首页。
// 进度跟 Store 的启动加载真实挂钩（摘要 0→0.1，11 个客户端完整规则各 +0.9/11，
// 失败也计入，不会卡住）；加载全在后台，主线程只驱动进度条。
struct LaunchView: View {
    @ObservedObject var store: MagicRuleStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.amberGradient)
                        .frame(width: 88, height: 88)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    Text("Magic")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Rule")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Text("规则索引 · 11 个客户端")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                VStack(spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.accentSoft)
                            Capsule()
                                .fill(Theme.amberGradient)
                                .frame(width: max(geo.size.width * 0.02, geo.size.width * store.launchProgress))
                        }
                    }
                    .frame(height: 8)
                    .animation(.easeOut(duration: 0.25), value: store.launchProgress)
                    HStack {
                        Text(store.launchStatusText)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(Int(store.launchProgress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 48)
                Spacer()
                Text("数据来自 MagicRule")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.bottom, 40)
            }
        }
    }
}
