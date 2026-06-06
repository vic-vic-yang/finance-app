import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';

final NumberFormat _money = NumberFormat('#,##0.##', 'zh_CN');
final NumberFormat _money0 = NumberFormat('#,##0', 'zh_CN');

/// 金额格式化：带千分位。[decimals]=true 保留 ≤2 位小数。
String toolMoney(num v, {bool decimals = true}) =>
    decimals ? _money.format(v) : _money0.format(v.round());

/// 解析输入框文本为 double，空 / 非法 → 0
double toolParse(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

/// 工具页统一的数字输入框
class ToolNumField extends StatelessWidget {
  const ToolNumField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.suffix,
    this.allowDecimal = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? suffix;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            RegExp(allowDecimal ? r'[0-9.]' : r'[0-9]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        suffixStyle: TextStyle(color: AppColors.text2, fontSize: 14),
      ),
    );
  }
}

/// 两段式胶囊切换（如 等额本息 / 等额本金）
class ToolSegToggle extends StatelessWidget {
  const ToolSegToggle({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: index == i ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          index == i ? FontWeight.w600 : FontWeight.w500,
                      color: index == i
                          ? AppColors.onPrimary
                          : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 结果卡：标题 + 若干行
class ToolResultCard extends StatelessWidget {
  const ToolResultCard({
    super.key,
    required this.title,
    required this.children,
    this.accent,
  });

  final String title;
  final List<Widget> children;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent ?? AppColors.text2)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// 结果行：左标签 + 右数值。[emphasize] 放大加粗、用主色。
class ToolResultRow extends StatelessWidget {
  const ToolResultRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: emphasize ? 6 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: emphasize ? 15 : 14,
                    fontWeight:
                        emphasize ? FontWeight.w600 : FontWeight.w400,
                    color: emphasize ? AppColors.text1 : AppColors.text2)),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: TextStyle(
                  fontSize: emphasize ? 22 : 15,
                  fontWeight:
                      emphasize ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: emphasize ? -0.5 : 0,
                  color: valueColor ??
                      (emphasize ? AppColors.primary : AppColors.text1))),
        ],
      ),
    );
  }
}

/// 表单卡片：包裹一组输入框
class ToolFormCard extends StatelessWidget {
  const ToolFormCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) spaced.add(const SizedBox(height: 14));
    }
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced,
      ),
    );
  }
}
