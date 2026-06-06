import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import 'loan_calculator_screen.dart';
import 'tax_calculator_screen.dart';
import 'investment_calculator_screen.dart';
import 'exchange_screen.dart';
import 'stock_screen.dart';

/// 工具箱：一组纯本地计算的财务小工具（不联网、不碰账本数据、零隐私风险）。
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <_ToolItem>[
      _ToolItem(
        icon: '🏦',
        title: '贷款计算器',
        subtitle: '房贷车贷通用：等额本息/本金、提前还款省多少利息',
        builder: (_) => const LoanCalculatorScreen(),
      ),
      _ToolItem(
        icon: '🧾',
        title: '个税计算器',
        subtitle: '五险一金、专项附加扣除，算到手工资',
        builder: (_) => const TaxCalculatorScreen(),
      ),
      _ToolItem(
        icon: '📈',
        title: '复利 / 定投计算器',
        subtitle: '每月定投滚到 N 年后值多少钱',
        builder: (_) => const InvestmentCalculatorScreen(),
      ),
      _ToolItem(
        icon: '💱',
        title: '汇率换算',
        subtitle: '最新汇率，常用币种实时换算',
        builder: (_) => const ExchangeScreen(),
      ),
      _ToolItem(
        icon: '🔍',
        title: '股票分析',
        subtitle: '查询并收藏股票，看关键指标 + 评级 + AI 分析，随时更新',
        builder: (_) => const StockScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '工具箱'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                '都是纯本地计算，结果不会上传，放心算。',
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
            ),
            for (final t in tools)
              GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                radius: 16,
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: t.builder),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                        child:
                            Text(t.icon, style: const TextStyle(fontSize: 22))),
                  ),
                  title: Text(t.title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(t.subtitle,
                        style:
                            TextStyle(fontSize: 12, color: AppColors.text2)),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: AppColors.text2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolItem {
  final String icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  _ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}
