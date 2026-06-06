import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../crypto/crypto_bootstrap.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/glass.dart';

/// 忘记密码：用恢复码验证 → 重置密码 → 自动登录
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _userCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _loading = false;
  String _stage = '';

  @override
  void dispose() {
    _userCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _userCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    final pwd = _passCtrl.text;
    final conf = _confCtrl.text;
    if (username.isEmpty || code.isEmpty || pwd.isEmpty) {
      _snack('请填写完整');
      return;
    }
    if (pwd.length < 6) {
      _snack('新密码至少 6 位');
      return;
    }
    if (pwd != conf) {
      _snack('两次密码不一致');
      return;
    }

    setState(() {
      _loading = true;
      _stage = '验证恢复码…';
    });
    try {
      // 1. 拿 salt + 恢复码加密的 privKey 密文
      final start = await ApiService.recoverStart(username);
      final salt = start['kdfSalt'] as String?;
      final privByRec = start['sm2PrivByRecovery'] as String?;
      if (salt == null || privByRec == null) {
        _snack('账户没有启用恢复码，无法找回');
        return;
      }

      // 2. 在 isolate 里用恢复码解出 privKey
      setState(() => _stage = '解密身份密钥…');
      final privHex = await CryptoBootstrap.decryptPrivateKeyByRecoveryAsync(
        recoveryCode: code,
        privByRecoveryBase64: privByRec,
        saltBase64: salt,
      );

      // 3. 用新密码 + 同 salt 重新加密 privKey
      setState(() => _stage = '设置新密码…');
      final newPrivByPwd =
          await CryptoBootstrap.reencryptPrivByPasswordAsync(
        privateKeyHex: privHex,
        newPassword: pwd,
        saltBase64: salt,
      );

      // 4. POST → 服务端验证恢复码 + 改 bcrypt + 发 token
      final res = await ApiService.recoverFinish(
        username: username,
        recoveryCode: code,
        newPassword: pwd,
        sm2PrivByPwd: newPrivByPwd,
      );
      if (res['token'] == null) {
        _snack(res['message']?.toString() ?? '恢复失败');
        return;
      }

      // 5. 把 KeyChain 填好（用新返回的 keyBundle）
      final bundle = res['keyBundle'] as Map<String, dynamic>?;
      await KeyChain.instance.setSelf(
        pubKey: (bundle?['sm2PubKey'] as String?) ?? '',
        privKey: privHex,
        kdfSaltBase64: salt,
        persist: true,
      );

      // 6. 拉所有账本的 DEK 并在 isolate 批量解开
      try {
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
      } catch (_) {}

      // 顺手做一次 pending wrap
      PendingDekResolver.resetCooldown();
      unawaited(PendingDekResolver.resolveAll());

      if (!mounted) return;
      _snack('密码已重置，正在进入');
      Navigator.pushNamedAndRemoveUntil(context, '/main', (_) => false);
    } catch (e) {
      _snack('恢复失败：${e.toString()}');
    } finally {
      if (mounted) setState(() { _loading = false; _stage = ''; });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: AppColors.expense,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      appBar: const AuraAppBar(title: '找回密码'),
      body: AuraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('用注册时保存的恢复码重置密码',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.text2,
                              height: 1.5)),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '· 恢复码格式如 "ABCD-1234-…"（32 位 hex，4 个一组）\n'
                        '· 不区分大小写\n'
                        '· 验证通过后将自动登录',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.text3, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GlassCard(
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('用户名'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _userCtrl,
                            decoration: const InputDecoration(
                              hintText: '注册时的用户名',
                              prefixIcon:
                                  Icon(Icons.person_outline_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _label('恢复码'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _codeCtrl,
                            decoration: const InputDecoration(
                              hintText: 'ABCD-1234-…',
                              prefixIcon:
                                  Icon(Icons.shield_outlined, size: 18),
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 16),
                          _label('新密码'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              hintText: '至少 6 个字符',
                              prefixIcon:
                                  Icon(Icons.lock_outline_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _label('确认新密码'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _confCtrl,
                            obscureText: true,
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              hintText: '再次输入',
                              prefixIcon:
                                  Icon(Icons.lock_outline_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
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
                                            ? '处理中…'
                                            : _stage),
                                      ],
                                    )
                                  : const Text('确认重置并登录'),
                            ),
                          ),
                        ],
                      ),
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

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text1));
}
