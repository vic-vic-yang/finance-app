import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/siku_ui.dart';
import 'auto_bookkeeping_screen.dart';
import 'cfo_screen.dart';
import 'forecast_screen.dart';
import 'health_screen.dart';
import 'merchant_insights_screen.dart';
import 'monthly_report_screen.dart';
import 'notifications_screen.dart';
import 'reconcile_screen.dart';

/// 智能管家：AI / 自动化功能的聚合入口。
/// 「我的」页只保留基础功能，智能功能收拢到这里，
/// 每个入口带一句说明，避免宫格平铺不知用哪个。
class SmartHubScreen extends StatelessWidget {
  const SmartHubScreen({super.key});

  static const _automation = <_HubItem>[
    _HubItem('⚡', '自动记账', '支付通知自动生成草稿，确认即入账',
        AutoBookkeepingScreen()),
    _HubItem('🔔', '通知中心', '每日财务提醒与预警汇总', NotificationsScreen()),
    _HubItem('🤵', '私人 CFO', '审批制财务建议，可授权自动执行', CfoScreen()),
  ];

  static const _insights = <_HubItem>[
    _HubItem('📈', '现金流预测', '月末结余早知道', ForecastScreen()),
    _HubItem('🧾', '对账中心', '余额 / 重复 / 缺腿四项体检', ReconcileScreen()),
    _HubItem('🏥', '财务健康分', '五维评分与改进建议', HealthScreen()),
    _HubItem('🏪', '商户画像', '本机计算的消费图谱，数据不出设备',
        MerchantInsightsScreen()),
    _HubItem('📊', 'AI 月报', '每月收支叙事报告', MonthlyReportScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '智能管家'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(
              'AI 在你账本的明文字段上工作，备注等隐私内容全程加密。',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.text3),
            ),
            const SectionHeader(title: '自动化', top: 18),
            for (final item in _automation) ...[
              _entry(context, item),
              const SizedBox(height: 10),
            ],
            const SectionHeader(title: '分析与洞察', top: 14),
            for (final item in _insights) ...[
              _entry(context, item),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, _HubItem item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => item.screen),
      ),
      child: GlassCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(item.icon, style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

class _HubItem {
  final String icon;
  final String title;
  final String subtitle;
  final Widget screen;
  const _HubItem(this.icon, this.title, this.subtitle, this.screen);
}
