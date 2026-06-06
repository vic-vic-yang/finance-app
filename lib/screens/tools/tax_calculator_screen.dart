import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import 'tools_common.dart';

/// 个税计算器：工资薪金综合所得（年度累计），按 2019 起施行的七级超额累进。纯本地计算。
class TaxCalculatorScreen extends StatefulWidget {
  const TaxCalculatorScreen({super.key});

  @override
  State<TaxCalculatorScreen> createState() => _TaxCalculatorScreenState();
}

class _TaxCalculatorScreenState extends State<TaxCalculatorScreen> {
  final _salaryCtrl = TextEditingController(); // 税前月薪
  final _insuranceCtrl = TextEditingController(); // 五险一金（个人月缴）
  final _specialCtrl = TextEditingController(); // 专项附加扣除（月）

  // 年度综合所得税率表（应纳税所得额，速算扣除数）
  static const _brackets = [
    [36000.0, 0.03, 0.0],
    [144000.0, 0.10, 2520.0],
    [300000.0, 0.20, 16920.0],
    [420000.0, 0.25, 31920.0],
    [660000.0, 0.30, 52920.0],
    [960000.0, 0.35, 85920.0],
    [double.infinity, 0.45, 181920.0],
  ];

  static const double _threshold = 5000; // 月起征点

  @override
  void initState() {
    super.initState();
    for (final c in [_salaryCtrl, _insuranceCtrl, _specialCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_salaryCtrl, _insuranceCtrl, _specialCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _salary => toolParse(_salaryCtrl.text);
  double get _insurance => toolParse(_insuranceCtrl.text);
  double get _special => toolParse(_specialCtrl.text);

  /// 计算年度个税
  ({double annualTax, double taxable, double rate, double deduction}) _calc() {
    final annualTaxable =
        ((_salary - _insurance - _threshold - _special) * 12).clamp(0.0, double.infinity);
    for (final b in _brackets) {
      if (annualTaxable <= b[0]) {
        final tax = annualTaxable * b[1] - b[2];
        return (
          annualTax: tax < 0 ? 0 : tax,
          taxable: annualTaxable,
          rate: b[1],
          deduction: b[2],
        );
      }
    }
    return (annualTax: 0, taxable: 0, rate: 0, deduction: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _salary > 0;
    final res = _calc();
    final monthlyTax = res.annualTax / 12;
    final afterTaxMonth = _salary - _insurance - monthlyTax;
    final afterTaxYear = afterTaxMonth * 12;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '个税计算器'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            ToolFormCard(
              children: [
                ToolNumField(
                  controller: _salaryCtrl,
                  label: '税前月薪',
                  hint: '例如 20000',
                  suffix: '元',
                ),
                ToolNumField(
                  controller: _insuranceCtrl,
                  label: '五险一金（个人月缴）',
                  hint: '没有可不填',
                  suffix: '元',
                ),
                ToolNumField(
                  controller: _specialCtrl,
                  label: '专项附加扣除（每月合计）',
                  hint: '子女教育、房贷利息、赡养老人…',
                  suffix: '元',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (hasInput) ...[
              ToolResultCard(
                title: '到手收入',
                children: [
                  ToolResultRow(
                      label: '税后月收入',
                      value: '¥${toolMoney(afterTaxMonth)}',
                      emphasize: true),
                  const Divider(height: 18),
                  ToolResultRow(
                      label: '每月个税',
                      value: '¥${toolMoney(monthlyTax)}',
                      valueColor: AppColors.expense),
                  ToolResultRow(
                      label: '税后年收入', value: '¥${toolMoney(afterTaxYear)}'),
                ],
              ),
              const SizedBox(height: 14),
              ToolResultCard(
                title: '计税明细（年度）',
                children: [
                  ToolResultRow(
                      label: '年应纳税所得额',
                      value: '¥${toolMoney(res.taxable)}'),
                  ToolResultRow(
                      label: '适用税率',
                      value: '${(res.rate * 100).toStringAsFixed(0)}%'),
                  ToolResultRow(
                      label: '速算扣除数',
                      value: '¥${toolMoney(res.deduction)}'),
                  ToolResultRow(
                      label: '全年个税',
                      value: '¥${toolMoney(res.annualTax)}',
                      valueColor: AppColors.expense),
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
            child: Text('填入税前月薪即可估算到手工资与个税',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        ]),
      );

  Widget _tip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '说明：按月薪稳定、全年 5000/月起征（年 6 万）的综合所得估算；'
          '年终奖单独计税、年中调薪、多处收入等情形未计入，实际以汇算清缴为准。',
          style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.5),
        ),
      );
}
