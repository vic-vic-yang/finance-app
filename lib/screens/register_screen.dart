import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../crypto/crypto_bootstrap.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/pending_dek_resolver.dart';

RegisterBundle _prepareRegistrationIsolate(String password) {
  return CryptoBootstrap.prepareRegistration(password: password);
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  Future<void> _register() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm  = _confirmCtrl.text;
    if (username.isEmpty || password.isEmpty) { _snack('请填写用户名和密码'); return; }
    if (password != confirm) { _snack('两次密码不一致'); return; }
    if (password.length < 6) { _snack('密码至少6个字符'); return; }

    setState(() => _loading = true);
    try {
      // 1. 本地预先生成所有密钥材料
      // PBKDF2 100k × 2 + SM2 keypair 是纯 CPU 重活：
      //   - Android AOT：约 2-5 秒
      //   - Flutter Web (Dart→JS)：可能 30-60 秒
      // 用 compute() 在移动端会跑到独立 isolate，UI 不卡；
      // Web 上 compute() 会退化到主线程，但至少不会更糟。
      final sw = Stopwatch()..start();
      final bundle = await compute(_prepareRegistrationIsolate, password);
      debugPrint('[register] crypto bundle ready in ${sw.elapsedMilliseconds}ms');

      // 2. 把密文 / 公钥 上传服务端
      final result = await ApiService.register(
        username: username,
        password: password,
        sm2PubKey: bundle.sm2PubKey,
        sm2PrivByPwd: bundle.sm2PrivByPwdBase64,
        sm2PrivByRecovery: bundle.sm2PrivByRecoveryBase64,
        kdfSalt: bundle.kdfSaltBase64,
        recoveryHash: bundle.recoveryHashBase64,
        personalLedgerDekWrapped: bundle.personalLedgerDekWrappedBase64,
      );
      if (!mounted) return;
      if (result['token'] == null) {
        _snack(result['message'] ?? '注册失败');
        return;
      }

      // 3. 把私钥写进 KeyChain（持久化，下次冷启动免输密码）
      await KeyChain.instance.setSelf(
        pubKey: bundle.sm2PubKey,
        privKey: bundle.privateKeyHex,
        persist: true,
      );
      // 4. 个人账本 DEK 直接落本地，省一次拉接口
      final user = result['user'] as Map<String, dynamic>?;
      final personalLedgerId = user?['currentLedgerId'] as String?;
      if (personalLedgerId != null) {
        // 用我们刚算好的 dek + dekWrappedBase64 直接装进缓存
        KeyChain.instance.loadDek(
          ledgerId: personalLedgerId,
          dekWrappedBase64: bundle.personalLedgerDekWrappedBase64,
          dekVersion: 1,
        );
      }

      // 5. 强制弹"保存恢复码"对话框，用户不点确认不能离开
      if (!mounted) return;
      await _showRecoveryCodeDialog(bundle.recoveryCode);

      // 6. 机会式补 wrap（新注册一般不会有 pending，但保留一致语义）
      PendingDekResolver.resetCooldown();
      unawaited(PendingDekResolver.resolveAll());

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      _snack('注册失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryCodeDialog(String code) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.shield_outlined,
              color: AppColors.warning, size: 22),
          SizedBox(width: 8),
          Text('请妥善保存恢复码',
              style: TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '· 你的账单、备注全部端到端加密，服务端无法解开\n'
                '· 忘记密码时，只有这串恢复码能还原你的数据\n'
                '· 请截图 / 复制 / 抄到密码管理器中保存\n'
                '· 该恢复码不会再显示，丢失等于数据永久无法找回',
                style: TextStyle(
                    fontSize: 12, color: AppColors.text2, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('恢复码已复制到剪贴板'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已保存'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
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
              const SizedBox(height: 24),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
              const SizedBox(height: 16),
              Text('创建账号',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text1,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('填写信息开始记账之旅',
                  style: TextStyle(fontSize: 14, color: AppColors.text2)),
              const SizedBox(height: 40),
              _label('用户名'),
              const SizedBox(height: 8),
              TextField(
                controller: _userCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: '2~20个字符',
                  prefixIcon: Icon(Icons.person_outline_rounded,
                      color: AppColors.text2, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              _label('密码'),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure1,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: '至少6个字符',
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: AppColors.text2, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure1
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.text2, size: 20,
                    ),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _label('确认密码'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure2,
                onSubmitted: (_) => _register(),
                decoration: InputDecoration(
                  hintText: '再次输入密码',
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: AppColors.text2, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure2
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.text2, size: 20,
                    ),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              ElevatedButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.onPrimary)),
                          const SizedBox(width: 10),
                          const Text('正在生成加密密钥...'),
                        ],
                      )
                    : const Text('注册'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('已有账号？',
                      style: TextStyle(color: AppColors.text2, fontSize: 14)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('去登录',
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

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text1));
}
