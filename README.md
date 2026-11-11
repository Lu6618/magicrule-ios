# MagicRule iOS

MagicRule 规则索引浏览器：浏览 11 个客户端（QuantumultX / Loon / Shadowrocket / Surge / SingBox / Egern / Mihomo / Stash / Surfboard / AdGuard / Anywhere）的分流与去广告规则索引，支持搜索、详情查看、复制与分享。

- 数据来源：[MagicRule](https://magicrule.pages.dev/)，App 内置索引数据，开箱即用；联网时自动从 Cloudflare Worker 拉取最新数据并缓存。
- 构建：GitHub Actions（macos-15，`xcodebuild archive`，unsigned IPA），dispatch 时 `publish_release=true` 会发布 Release。
- 仅 unsigned 构建，安装前需自行签名。
