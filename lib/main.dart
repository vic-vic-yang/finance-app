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
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/pending_dek_resolver.dart';

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
  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance.revision,
      builder: (_, __) => MaterialApp(
        title: '司库',
        debugShowCheckedModeBanner: false,
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

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.pushReplacementNamed(
        context, token != null ? '/main' : '/login');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💰', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('司库',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: -0.5)),
            ],
          ),
        ),
      );
}
