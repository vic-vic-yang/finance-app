import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import 'agreement_screen.dart';

/// 欢迎 / 引导页：品牌 + 三个卖点 + 进入按钮 + 协议页脚。
/// 未登录用户进入 App 时展示，点「开启财务新篇章」去登录。
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _features = [
    [Icons.upload_file_rounded, '智能导入', '支持文件一键导入，轻松迁移历史账单。'],
    [Icons.insights_rounded, 'AI 分析', '深度财务洞察，助您优化支出结构。'],
    [Icons.lock_rounded, '隐私安全', '端到端加密技术，全方位守护您的财务隐私。'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AuraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 品牌
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white, // design:ok 品牌 logo 白色底砖装饰
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset('assets/icon/app_icon.png',
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '司库  '),
                        TextSpan(
                            text: '· ',
                            style: TextStyle(color: AppColors.primary)),
                        const TextSpan(text: '智能财务管家'),
                      ]),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '您的私人财富守护者，让每一分钱都有迹可循。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.5,
                            color: AppColors.text2),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // 卖点
                    for (final f in _features) ...[
                      _featureCard(f[0] as IconData, f[1] as String,
                          f[2] as String),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 18),
                    // 进入
                    SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                            context, '/login'),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text('开启财务新篇章',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const AgreementFooter(prefix: '点击上方按钮即代表您同意'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String desc) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const SizedBox(height: 3),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
