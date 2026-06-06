# 财记 · 前端 (finance-app)

「财记」个人 / 家庭记账应用的 **Flutter 客户端**（移动 + Web）。支持共享账本、端到端加密、AI 智能导入、私人 CFO 助手、财经资讯与财务工具。

后端仓库：[finance-api](https://github.com/vic-vic-yang/finance-api)（NestJS）。

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.41 / Dart 3.x |
| 字体 | Outfit（`google_fonts`，首次启动 CDN 下载缓存） |
| 设计 | Aura Finance「Quiet Luxury」玻璃拟态系统 |
| 国密加密 | SM2/SM3/SM4（`gm_crypto` / `dart_sm_new` / `pointycastle`） |
| 安全存储 | `flutter_secure_storage`（私钥 / DEK 缓存） |
| 网络 | `http` |
| 图表 | `fl_chart` |

## 快速开始

```bash
flutter pub get              # 安装依赖
flutter run -d chrome        # Web 调试（自动用 localhost:3000/api）
flutter run                  # 连真机 / 模拟器
```

### 构建

```bash
flutter build apk --release                 # 整包 APK
flutter build apk --release --split-per-abi # 分架构 APK（每个更小）
```

热重载：`r` 热重载（UI），`R` 热重启（`initState`/新文件/顶层变量），`q` 退出（改 `pubspec.yaml` 后需退出重来）。

## 后端地址配置

见 [`lib/services/api_service.dart`](lib/services/api_service.dart) 顶部：

- **Web 调试**：自动用 `http://localhost:3000/api`
- **移动端**：默认走公网 `_publicHost`（Cloudflare Tunnel 域名）

改成你自己的后端，把 `_publicHost` 换成你的地址即可。

## 架构

```
lib/
├── main.dart            入口：恢复密钥、预热连接、路由
├── core/                主题(Aura 设计系统) / 主题服务 / 刷新总线
├── crypto/              SM2 密钥引导 + KeyChain（私钥 / 每账本 DEK）
├── models/              Account / Bill / Budget / Category / Ledger / NewsArticle …
├── services/            api_service(全部 REST) / auth_service / 各业务服务
├── widgets/             glass.dart（AuraBackground / GlassCard / GlassNavBar / AuraAppBar …）
└── screens/
    ├── login / register / forgot_password   认证（玻璃风）
    ├── main_screen      底部 5 tab：主页 / 统计 / 资讯 / 预算 / 目标
    ├── home_screen      结余卡(含记一笔) / 快捷工具 / 预算 / 账户 / 最近账单
    ├── add_bill_screen  记一笔（自定义数字键盘 + 转账）
    ├── stats / budgets / goals / bills / accounts / account_detail
    ├── ai_imports_screen  AI 智能导入
    ├── cfo_screen       私人 CFO 复盘
    ├── chat_screen      AI 对话助手（可对话记账 / 改预算）
    ├── monthly_report_screen  月报
    ├── news_screen / news_detail_screen  财经资讯（列表 + AI 要点详情）
    └── tools/           工具箱：贷款 / 个税 / 复利定投 计算器 + 汇率换算
```

### 关键设计

- **端到端加密**：注册时客户端生成 SM2 密钥对；`KeyChain` 单例管理私钥与每账本 DEK，账单备注 / 账户名加密后才上传，服务端只见密文。
- **状态管理**：轻量。全局 `ValueNotifier` 事件总线（`refresh_bus.dart`）+ `SharedPreferences` 持久化登录态，无重型状态框架。
- **玻璃风 UI**：所有页面基于 `AuraBackground` + `GlassCard`；弹窗 / 输入框 / 导航统一在 `core/theme.dart` 的 `ThemeData` 里。

## 约定

- 用户可见文案全为简体中文，locale 固定 `zh_CN`。
- 所有 API 走后端 `/api` 前缀；金额展示与计算注意精度。
- 财经资讯的抓取时机完全由后端控制，前端无手动抓取入口（下拉仅重读列表）。

