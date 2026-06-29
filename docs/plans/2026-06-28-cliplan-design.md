# ClipLAN for macOS: 一次性实现计划

## 目标

开发一个本地优先的 macOS 剪贴板历史工具。应用需要在本机高性能保存剪贴板历史，并支持局域网内多台 Mac 自动同步和手动推送剪贴板内容。

## 范围

| 需求 | 实现策略 | 验收方式 |
| --- | --- | --- |
| 后台常驻 | SwiftUI `MenuBarExtra` + 常规 Dock 窗口 | 启动后菜单栏可操作，主窗口可打开 |
| 剪贴板监听 | 监听 `NSPasteboard.changeCount`，避免高频读取内容 | 复制文本/图片/文件后进入历史 |
| 历史存储 | SQLite + WAL；payload 放磁盘 blob | 重启后历史仍在 |
| 搜索 | SQLite FTS5 索引摘要、来源 App | 搜索关键词能过滤历史 |
| 快速选择面板 | SwiftUI 原生窗口，左侧过滤、右侧详情、快捷操作 | 快速浏览、Pin、收藏、粘贴 |
| 自动粘贴 | 写回 `NSPasteboard` 后发送 `Cmd+V` | 选择记录后可粘贴到前台 App |
| 局域网发现 | Network.framework Bonjour (`_cliplan._tcp`) | 同网设备自动出现在侧栏/状态区 |
| 局域网同步 | JSON line 协议；metadata + 小 payload inline；大 payload 按需请求 | 两台设备运行后复制内容互相同步 |
| 手动推送 | 选择记录后发送到已发现设备，并可在目标端激活剪贴板 | 目标设备收到并写入剪贴板 |
| 性能保护 | 大小阈值、异步写库、去重、懒加载、保留策略 | 大内容不阻塞 UI，不无限增长 |

## 性能约束

- 监听层只比较 `NSPasteboard.changeCount`，变化后再读取内容。
- 单条默认上限 50 MB，超过后跳过，避免大文件拖垮内存。
- SQLite 开启 `WAL`、`synchronous=NORMAL`、索引 `created_at` / `content_hash`。
- 大 payload 不写入 SQLite；写到 `Application Support/ClipLAN/blobs`。
- 用 SHA256 对 payload 去重；重复复制同一内容时更新排序，不重复存储。
- UI 列表默认只取最近 200 条，搜索交给 FTS5。
- 局域网自动同步只 inline 小 payload，默认 2 MB；更大内容按需请求。
- 保留策略默认最多 10,000 条，Pin/收藏不自动清理。

## 架构

```text
ClipLAN.app
  App/
    PasteApp, AppDelegate, GlobalHotKeyManager, ClipboardAppModel
  Views/
    ContentView, EntryListView, EntryDetailView, SettingsView, MenuBarView

PasteCore
  Models/
    ClipboardEntry, ClipboardContentType, PeerDevice
  Stores/
    ClipboardStore(SQLite), PayloadStore
  Services/
    ClipboardReader, ClipboardMonitor, PasteExecutor, LANSyncService
  Support/
    ApplicationPaths, ContentHasher, Date/SQLite helpers
```

## 权限和限制

- 自动发送 `Cmd+V` 需要辅助功能权限；没有权限时仍会把内容写入系统剪贴板，用户可手动粘贴。
- SwiftPM 打包的本地 `.app` 不默认启用 App Sandbox；这是自用本地工具的最小可行路径。
- 代码、资源、文案和图标使用自定义实现。

## 构建与运行

- 项目使用 SwiftPM，最低 macOS 14。
- `./script/build_and_run.sh` 负责 kill、build、打包 `dist/ClipLAN.app`、启动。
- `.codex/environments/environment.toml` 提供 Codex Run 按钮。
