import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

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
      final result = await ApiService.register(username, password);
      if (!mounted) return;
      if (result['token'] != null) {
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        _snack(result['message'] ?? '注册失败');
      }
    } catch (_) {
      _snack('网络错误，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary))
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
