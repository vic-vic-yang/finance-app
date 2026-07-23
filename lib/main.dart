import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'core/theme_service.dart';
import 'crypto/key_chain.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'screens/add_bill_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_service.dart';
import 'services/llm_config_service.dart';
import 'services/auth_service.dart';
import 'services/local_push_service.dart';
import 'services/pending_dek_resolver.dart';
import 'services/auto_bookkeeping_service.dart';
import 'screens/notifications_screen.dart';

/// 全局 Navigator key：本地推送点击回调等无 BuildContext 场景用来路由跳转
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService.instance.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  // 关键：把上次保存的 SM2 keypair（公钥+私钥）从 SecureStorage 恢复到内存
  // 否则用户重启 App 后直接进主页（JWT 没过期），创建账本时 wrap DEK 会
  // 报 "尚未加载用户公钥"
  await KeyChain.instance.restoreFromStorage();

  // 私钥恢复了 → 把所有账本的 DEK 也异步恢复（不阻塞 UI）
  unawaited(() async {
    if (!KeyChain.instance.hasKey) return;
    try {
      final res = await ApiService.getMyDeks();
      final list = (res['deks'] as List?) ?? [];
      for (final d in list) {
        try {
          KeyChain.instance.loadDek(
            ledgerId: d['ledgerId'] as String,
            dekWrappedBase64: d['dekWrapped'] as String,
            dekVersion: (d['dekVersion'] as num?)?.toInt() ?? 1,
          );
        } catch (_) {}
      }
      // 也顺手给 pending 成员补 wrap
      PendingDekResolver.resetCooldown();
      unawaited(PendingDekResolver.resolveAll());
    } catch (_) {}
  }());

  // 在用户慢慢输账号密码这几秒里，先把 TLS 连接建好，省 1.5+ 秒 TLS 握手
  unawaited(ApiService.prewarm());
  // 按当前登录账号加载其 AI 模型配置（未登录则为空）
  final savedUser = await AuthService.getUser();
  await LlmConfigService.instance.load(savedUser?['id'] as String?);
  // 启动自动记账通知监听（仅 Android 生效；幂等，未登录/未授权时静默）
  AutoBookkeepingService.instance.start();
  // 本地推送桥接：初始化 + 启动时检查一次新未读通知（App 内 async，不阻塞首屏）。
  // ⚠️ 边界：这不是离线推送——只在 App 启动 / 回到前台时生效，
  // App 被杀后收不到提醒（那需要 FCM / 厂商通道，本期不做）。
  unawaited(LocalPushService.instance
      .init(onOpenNotificationCenter: _openNotificationCenterFromPush)
      .then((_) => LocalPushService.instance.checkAndNotify()));
  runApp(const FinanceApp());
}

/// 点击系统本地通知 → 打开通知中心（未登录 / App 尚未就绪时静默跳过）
Future<void> _openNotificationCenterFromPush() async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  final token = await AuthService.getToken();
  if (token == null) return;
  nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
}

class FinanceApp extends StatefulWidget {
  const FinanceApp({super.key});

  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回到前台：检查一次新未读通知并补发本地推送（内部已做去重与静默降级）
    if (state == AppLifecycleState.resumed) {
      unawaited(LocalPushService.instance.checkAndNotify());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance.revision,
      builder: (_, __) => MaterialApp(
        title: '司库',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.build(),
        // 中文本地化：让 DatePicker / TimePicker / 系统对话框都说中文
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        locale: const Locale('zh', 'CN'),
        initialRoute: '/splash',
        routes: {
          '/splash':  (_) => const _SplashScreen(),
          '/welcome': (_) => const WelcomeScreen(),
          '/login':   (_) => const LoginScreen(),
          '/register':(_) => const RegisterScreen(),
          '/forgot-password': (_) => const ForgotPasswordScreen(),
          '/main':    (_) => const MainScreen(),
          '/add':     (_) => const AddBillScreen(),
        },
      ),
    );
  }
}

// ── Splash: auto-route based on auth state ────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
    _check();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    // 留足动画时间，整体观感更稳
    await Future.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;
    Navigator.pushReplacementNamed(
        context, token != null ? '/main' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final grad = AppColors.primaryGradient;
    final base = grad.first; // 深主题色（边缘）
    // 中心光晕：主题浅色再掺一点白，从中心向外逐渐过渡到 base
    final glow = Color.alphaBlend(Colors.white.withValues(alpha: 0.16), grad.last);
    final edge = Color.alphaBlend(Colors.black.withValues(alpha: 0.18), base);
    final fg = AppColors.onPrimaryGradient;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.18),
            radius: 1.15,
            colors: [glow, base, edge],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // logo：静态、无入场动画 —— 与原生闪屏的 logo 同位置同尺寸，无缝过渡
                    Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.16),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset('assets/icon/app_icon.png',
                              width: 96, height: 96, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 文案：仅这部分淡入，做点缀（logo 不动，避免跳变）
                    FadeTransition(
                      opacity: _fade,
                      child: Column(
                        children: [
                          Text('司库',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: fg,
                                  letterSpacing: 2)),
                          const SizedBox(height: 8),
                          Text('智能财务管家',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: fg.withValues(alpha: 0.6),
                                  letterSpacing: 4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部品牌签名
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: FadeTransition(
                  opacity: _fade,
                  child: Text('SI·KU  ·  让每一笔钱都心中有数',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: 0.4),
                          letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
