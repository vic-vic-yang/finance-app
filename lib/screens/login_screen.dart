import 'dart:async';

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../crypto/crypto_bootstrap.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/pending_dek_resolver.dart';

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

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _snack('请填写用户名和密码');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.login(username, password);
      if (!mounted) return;
      if (result['token'] == null) {
        _snack(result['message'] ?? '登录失败');
        return;
      }

      // 1. 用密码解出 SM2 私钥（PBKDF2 + SM4 大约 1~2 秒）
      final bundle = result['keyBundle'] as Map<String, dynamic>?;
      if (bundle == null ||
          bundle['sm2PubKey'] == null ||
          bundle['sm2PrivByPwd'] == null ||
          bundle['kdfSalt'] == null) {
        _snack('该账号尚未启用加密，请联系管理员或重新注册');
        return;
      }
      final privHex = await Future(() =>
          CryptoBootstrap.decryptPrivateKeyByPassword(
            password: password,
            privByPwdBase64: bundle['sm2PrivByPwd'] as String,
            saltBase64: bundle['kdfSalt'] as String,
          ));

      await KeyChain.instance.setSelf(
        pubKey: bundle['sm2PubKey'] as String,
        privKey: privHex,
        persist: true,
      );

      // 2. 拉取自己在所有账本里的 dekWrapped，全部解开缓存
      final deks = await ApiService.getMyDeks();
      final list = (deks['deks'] as List?) ?? [];
      for (final d in list) {
        try {
          KeyChain.instance.loadDek(
            ledgerId: d['ledgerId'] as String,
            dekWrappedBase64: d['dekWrapped'] as String,
            dekVersion: d['dekVersion'] as int,
          );
        } catch (_) {
          // 某个账本解不开（极少见，私钥不匹配）—— 跳过，其他账本仍可用
        }
      }

      // 3. 机会式：给所有账本里 pending 的新成员补 wrap DEK（不阻塞跳转）
      PendingDekResolver.resetCooldown();
      unawaited(PendingDekResolver.resolveAll());

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      _snack('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 64),
              // Logo
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: Text('💰', style: TextStyle(fontSize: 38)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  '财记',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '让财务一目了然',
                    style: TextStyle(fontSize: 14, color: AppColors.text2),
                  ),
                ),
              ),
              const SizedBox(height: 52),
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
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('登录'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('还没有账号？',
                      style: TextStyle(color: AppColors.text2, fontSize: 14)),
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
