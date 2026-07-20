# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

「司库」(finance-app) — the Flutter client (mobile + Web) for an AI-assisted personal/family finance manager. Pairs with the NestJS backend `finance-api`.

## Commands

```bash
flutter pub get                 # deps (rerun after pubspec changes)
flutter run -d chrome           # Web debug → auto uses http://localhost:3000/api
flutter run                     # device/emulator → uses public host (Cloudflare Tunnel)
flutter build apk --release [--split-per-abi]
```

**Correctness gate:** there is **no broad widget-test suite**. Validate changes with:
- `flutter analyze <file-or-dir>` — the primary check used throughout this codebase. Run after every change; treat `error •`/`warning •` as must-fix (pre-existing `withOpacity` info-lints are noise).
- `flutter test [path]` — only **pure-logic** units have tests (e.g. `test/funding_matcher_test.dart`). Most of the app is verified by analyze + manual run.

Hot-reload: `r` (UI), **`R` hot-restart** (needed after `initState` changes, new files, top-level/static changes), `q` to quit (required after `pubspec.yaml` changes).

Backend address is set at the top of `lib/services/api_service.dart` (`_publicHost`); web auto-targets `localhost:3000/api`.

## Architecture

Layers under `lib/`: `screens/` (pages), `widgets/` (the design system), `services/` (API + crypto + app services), `models/`, `core/` (theme + cross-cutting), `crypto/` (key management). Entry: `main.dart`.

### Client-side E2E crypto is the defining constraint

`crypto/key_chain.dart` (`KeyChain`) holds the **per-ledger DEK** (cached in `flutter_secure_storage`). The client **encrypts before sending and decrypts on read** — `Bill.noteCipher`, `Account.nameCipher`, etc. The server only stores ciphertext and never sees plaintext. SM2/SM3/SM4 via `gm_crypto`/`dart_sm_new`/`pointycastle`; register generates a keypair + recovery code (`crypto/crypto_bootstrap.dart`).

Consequence: account **names** and bill **notes/merchants** are only readable on-device. Any feature that matches on those (e.g. mapping a statement's "付款方式" to an account in `services/funding_matcher.dart`) must run **client-side** — the server can't. Shared ledgers may arrive without a DEK yet (`services/pending_dek_resolver.dart` rehydrates/wraps DEKs).

### Theming (Aura "Quiet Luxury" glassmorphism)

`core/theme.dart` exposes `AppColors`/`AppTheme` as **getters** that read `core/theme_service.dart` (`ThemeService.instance`: light/dark + palette). Switching theme bumps `ThemeService.revision`; `MainScreen` listens and rebuilds the whole tree so the getters re-read new colors — so never cache an `AppColors.*` value, always read the getter.

`widgets/glass.dart` is the component library: `AuraBackground` (cream/obsidian base + radial blobs, place at the Scaffold's root), `GlassCard`, `GlassNavBar`, `ProfileAvatar`, `AiButton`, and the unified headers — `AuraSliverAppBar` (home, scrollable, frosted `BackdropFilter` bg so scrolled content doesn't bleed through) and `AuraAppBar` (other tabs + secondary pages, 64px). Glass look = `BackdropFilter` blur + translucent fill + ghost border over `AuraBackground`. Secondary (pushed) pages set `Scaffold(backgroundColor: AppColors.bg)` so the transparent app-bar strip matches the body in dark mode.

### Navigation & cross-screen refresh

`screens/main_screen.dart` = `IndexedStack` of 4 tabs (主页/统计/预算/目标) under one root `AuraBackground`, with `GlassNavBar` + a center docked FAB (记一笔 → `add_bill_screen`). Profile is a pushed page reached via the top-left avatar, not a tab. After any write, call `bumpRefresh()` (`core/refresh_bus.dart`, a global `ValueNotifier`); screens listen to `refreshBus` and reload.

`services/api_service.dart` uses a single long-lived HTTP client (TLS reuse); `_post` accepts a custom `timeout` (the AI apply call uses 120s for large batches).

### AI import & input flows

- **File import** (`screens/ai_imports_screen.dart`, `_autoApplyOne`): fetch drafts → per-draft resolve the real funding account (`funding_matcher.dart` normalize + match decrypted account names + `payment_method_map.dart` memory; prompts to confirm unmatched, remembers) → split into bills vs transfers by `direction` → encrypt notes → `aiApplyImport(bills, transfers)`.
- **NL记账**: 独立输入组件（旧 `widgets/nl_input_section.dart`）已移除，对话式记账/查询统一走 `screens/chat_screen.dart`（司库助手）；`ApiService.aiParseText` 接口仍保留但当前无调用方。
- Shared pickers live in `add_bill_screen.dart` and are reused (`CategoryPickerSheet`, `AccountPickerSheet`).
