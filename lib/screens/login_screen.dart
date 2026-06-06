import 'dart:async';

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../crypto/crypto_bootstrap.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/glass.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  /// 当前正在做什么 —— 显示在按钮上让用户知道进度
  String _stage = '';

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _snack('请填写用户名和密码');
      return;
    }
    setState(() {
      _loading = true;
      _stage = '正在登录…';
    });
    // 网络慢时给用户一个进度暗示，不要让 spinner 一直转不变化
    final slowHint = Timer(const Duration(seconds: 3), () {
      if (mounted && _stage == '正在登录…') {
        setState(() => _stage = '服务器响应较慢，请稍候…');
      }
    });
    try {
      final result = await ApiService.login(username, password);
      slowHint.cancel();
      if (!mounted) return;
      if (result['token'] == null) {
        _snack(result['message'] ?? '登录失败');
        return;
      }

      final bundle = result['keyBundle'] as Map<String, dynamic>?;
      if (bundle == null ||
          bundle['sm2PubKey'] == null ||
          bundle['sm2PrivByPwd'] == null ||
          bundle['kdfSalt'] == null) {
        _snack('该账号尚未启用加密，请联系管理员或重新注册');
        return;
      }

      // 1. 用密码解出 SM2 私钥（PBKDF2 100k）—— 在独立 isolate 跑，UI 不冻结
      setState(() => _stage = '解密身份密钥…');
      final privHex = await CryptoBootstrap.decryptPrivateKeyByPasswordAsync(
        password: password,
        privByPwdBase64: bundle['sm2PrivByPwd'] as String,
        saltBase64: bundle['kdfSalt'] as String,
      );

      await KeyChain.instance.setSelf(
        pubKey: bundle['sm2PubKey'] as String,
        privKey: privHex,
        kdfSaltBase64: bundle['kdfSalt'] as String,
        persist: true,
      );

      // 2. 拉取所有账本的 dekWrapped + 在 isolate 里批量 SM2 解密
      setState(() => _stage = '加载账本密钥…');
      final deks = await ApiService.getMyDeks();
      final list = (deks['deks'] as List?) ?? [];
      if (list.isNotEmpty) {
        final items = <DekToUnpack>[
          for (final d in list)
            DekToUnpack(
              ledgerId: d['ledgerId'] as String,
              dekWrappedBase64: d['dekWrapped'] as String,
              dekVersion: (d['dekVersion'] as num?)?.toInt() ?? 1,
            ),
        ];
        final unpacked = await CryptoBootstrap.decryptManyDeksAsync(
          privateKeyHex: privHex,
          deks: items,
        );
        for (final item in items) {
          final raw = unpacked[item.ledgerId];
          if (raw != null) {
            KeyChain.instance.putDek(
              ledgerId: item.ledgerId,
              rawDek: raw,
              dekVersion: item.dekVersion,
            );
          }
        }
      }

      // 3. 机会式补 wrap，不阻塞跳转
      PendingDekResolver.resetCooldown();
      unawaited(PendingDekResolver.resolveAll());

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      _snack('登录失败：$e');
    } finally {
      slowHint.cancel();
      if (mounted) setState(() { _loading = false; _stage = ''; });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.expense,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AuraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 品牌 logo —— 主色渐变 + 柔和环境阴影
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppColors.primaryGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.22),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('💰', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '财记',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '让财务一目了然',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.text2),
                    ),
                    const SizedBox(height: 34),
                    // 玻璃表单卡
                    GlassCard(
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('用户名'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _userCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: '请输入用户名',
                              prefixIcon: Icon(Icons.person_outline_rounded,
                                  color: AppColors.text2, size: 20),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _label('密码'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              hintText: '请输入密码',
                              prefixIcon: Icon(Icons.lock_outline_rounded,
                                  color: AppColors.text2, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.text2,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.onPrimary),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(_stage.isEmpty
                                            ? '登录中…'
                                            : _stage),
                                      ],
                                    )
                                  : const Text('登录'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/forgot-password'),
                        child: Text('忘记密码？用恢复码找回',
                            style: TextStyle(
                                color: AppColors.text2, fontSize: 13)),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('还没有账号？',
                            style: TextStyle(
                                color: AppColors.text2, fontSize: 14)),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/register'),
                          child: const Text('立即注册',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.text1,
        ),
      );
}
