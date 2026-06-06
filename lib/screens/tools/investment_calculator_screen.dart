import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import 'tools_common.dart';

/// 复利 / 定投计算器：初始本金 + 每月定投，按年化收益月复利滚动。纯本地计算。
class InvestmentCalculatorScreen extends StatefulWidget {
  const InvestmentCalculatorScreen({super.key});

  @override
  State<InvestmentCalculatorScreen> createState() =>
      _InvestmentCalculatorScreenState();
}

class _InvestmentCalculatorScreenState
    extends State<InvestmentCalculatorScreen> {
  final _principalCtrl = TextEditingController(); // 初始本金
  final _monthlyCtrl = TextEditingController(); // 每月定投
  final _rateCtrl = TextEditingController(text: '6'); // 年化收益率 %
  final _yearsCtrl = TextEditingController(text: '10'); // 年限

  @override
  void initState() {
    super.initState();
    for (final c in [_principalCtrl, _monthlyCtrl, _rateCtrl, _yearsCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_principalCtrl, _monthlyCtrl, _rateCtrl, _yearsCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _principal => toolParse(_principalCtrl.text);
  double get _monthly => toolParse(_monthlyCtrl.text);
  double get _annualRate => toolParse(_rateCtrl.text) / 100;
  int get _months => (toolParse(_yearsCtrl.text) * 12).round();

  @override
  Widget build(BuildContext context) {
    final months = _months;
    final hasInput = months > 0 && (_principal > 0 || _monthly > 0);

    final i = _annualRate / 12; // 月利率
    double fv;
    if (i == 0) {
      fv = _principal + _monthly * months;
    } else {
      final pow = math.pow(1 + i, months).toDouble();
      final fvPrincipal = _principal * pow;
      final fvContrib = _monthly * (pow - 1) / i; // 期末年金
      fv = fvPrincipal + fvContrib;
    }
    final invested = _principal + _monthly * months;
    final gain = fv - invested;
    final gainPct = invested > 0 ? gain / invested * 100 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '复利 / 定投计算器'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            ToolFormCard(
              children: [
                ToolNumField(
                  controller: _principalCtrl,
                  label: '初始本金',
                  hint: '一次性投入，可不填',
                  suffix: '元',
                ),
                ToolNumField(
                  controller: _monthlyCtrl,
                  label: '每月定投',
                  hint: '例如 2000',
                  suffix: '元',
                ),
                ToolNumField(
                  controller: _rateCtrl,
                  label: '预期年化收益率',
                  hint: '例如 6',
                  suffix: '%',
                ),
                ToolNumField(
                  controller: _yearsCtrl,
                  label: '投资年限',
                  hint: '例如 10',
                  suffix: '年',
                  allowDecimal: false,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (hasInput) ...[
              ToolResultCard(
                title: '到期结果',
                children: [
                  ToolResultRow(
                      label: '期末总额',
                      value: '¥${toolMoney(fv)}',
                      emphasize: true),
                  const Divider(height: 18),
                  ToolResultRow(
                      label: '累计投入', value: '¥${toolMoney(invested)}'),
                  ToolResultRow(
                      label: '累计收益',
                      value: '¥${toolMoney(gain)}',
                      valueColor: AppColors.income),
                  ToolResultRow(
                      label: '总收益率',
                      value: '${gainPct.toStringAsFixed(1)}%'),
                ],
              ),
              const SizedBox(height: 14),
              _tip(),
            ] else
              _emptyHint(),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint() => GlassCard(
        radius: 16,
        child: Row(children: [
          Icon(Icons.calculate_outlined, color: AppColors.text2, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('填入每月定投金额、年化收益与年限即可测算',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        ]),
      );

  Widget _tip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '说明：按固定年化、每月月末投入、收益月复利的理想模型测算。'
          '真实投资收益会波动，过往收益不代表未来，结果仅供参考。',
          style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.5),
        ),
      );
}
