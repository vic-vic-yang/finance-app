import 'package:flutter/material.dart';
import '../widgets/glass.dart';
import '../core/theme.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// 月报。通路 B：客户端解密所有账单本地聚合，把脱敏的"汇总数字"发给服务端，
/// 服务端调 LLM 生成中文叙事。原始 note 不出端。
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});
  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  /// 0=上月 / 1=本月（默认上月，更有总结意义）
  int _which = 0;
  bool _loading = false;
  String? _error;
  String? _ledgerId;

  // 聚合结果
  double _income = 0;
  double _expense = 0;
  List<_CatAgg> _byCategory = [];
  List<_MerchantAgg> _byMerchant = [];
  List<_WeekAgg> _byWeek = [];
  List<_BudgetExec> _budgetExec = [];

  // AI 生成的文案 + 关键点
  String? _narrative;
  List<_Highlight> _highlights = [];

  late DateTime _periodStart;
  late DateTime _periodEnd;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _narrative = null;
      _highlights = [];
    });
    try {
      // 1) 计算周期
      final now = DateTime.now();
      late final DateTime start;
      late final DateTime end;
      if (_which == 0) {
        // 上月
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0, 23, 59, 59);
      } else {
        // 本月
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
      _periodStart = start;
      _periodEnd = end;
      final user = await AuthService.getUser();
      _ledgerId = user?['currentLedgerId'] as String?;
      if (_ledgerId == null || _ledgerId!.isEmpty) {
        throw Exception('未选账本');
      }

      // 2) 拉所有该月账单
      final billsRes = await ApiService.getBills(
        startDate: DateFormat('yyyy-MM-dd').format(start),
        endDate: DateFormat('yyyy-MM-dd').format(end),
        limit: 2000,
      );
      final bills = (billsRes['bills'] as List? ?? [])
          .map((b) => Bill.fromJson(b as Map<String, dynamic>))
          .toList();

      // 3) 客户端聚合 —— 不上传 note 明文
      double income = 0, expense = 0;
      final byCat = <String, _CatAgg>{};
      final byMerchant = <String, _MerchantAgg>{};
      final byWeek = <String, _WeekAgg>{};
      for (final b in bills) {
        if (b.type == 'income') {
          income += b.amount;
        } else {
          expense += b.amount;
        }
        // 分类
        final cid = b.category.id;
        final cAgg = byCat.putIfAbsent(
          cid,
          () => _CatAgg(id: cid, name: b.category.name),
        );
        if (b.type == 'expense') {
          cAgg.amount += b.amount;
          cAgg.count++;
        }
        // 商户：取解密后 note 的第一段（· 分隔）
        if (b.type == 'expense') {
          final note = b.note;
          final merchant = note.split('·').first.trim();
          if (merchant.isNotEmpty &&
              !merchant.startsWith('【') &&
              merchant.length <= 16) {
            final mAgg = byMerchant.putIfAbsent(
              merchant,
              () => _MerchantAgg(merchant: merchant),
            );
            mAgg.amount += b.amount;
            mAgg.count++;
          }
          // 周分桶（本月第几周）
          final week = '第${((b.date.day - 1) ~/ 7) + 1}周';
          final wAgg = byWeek.putIfAbsent(week, () => _WeekAgg(week: week));
          wAgg.amount += b.amount;
        }
      }
      final byCatList = byCat.values.where((c) => c.amount > 0).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      final byMerchantList = byMerchant.values.toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      final byWeekList = byWeek.values.toList()
        ..sort((a, b) => a.week.compareTo(b.week));

      // 4) 预算执行
      final budgetExec = <_BudgetExec>[];
      try {
        final bdRes = await ApiService.getBudgets();
        final budgets = (bdRes['budgets'] as List? ?? [])
            .map((j) => Budget.fromJson(j as Map<String, dynamic>))
            .where((bd) => bd.period == 'MONTHLY')
            .toList();
        for (final bd in budgets) {
          final name = bd.categoryName ?? '总预算';
          if (_which == 1) {
            // 本月：服务端 spent 已经是当月
            budgetExec.add(_BudgetExec(
              categoryName: name,
              used: bd.spent,
              limit: bd.amount,
            ));
          } else {
            // 上月：从 byCat 找对应分类总和
            final c = byCatList.firstWhere(
              (x) => x.id == (bd.categoryId ?? ''),
              orElse: () => _CatAgg(id: '', name: name),
            );
            budgetExec.add(_BudgetExec(
              categoryName: name,
              used: c.amount,
              limit: bd.amount,
            ));
          }
        }
      } catch (_) {}

      // 5) 发服务端生成叙事
      final res = await ApiService.aiMonthlyReport(
        ledgerId: _ledgerId!,
        year: start.year,
        month: start.month,
        aggregates: {
          'income': income,
          'expense': expense,
          'byCategory': byCatList
              .take(15)
              .map((c) => {
                    'categoryId': c.id,
                    'name': c.name,
                    'amount': c.amount,
                    'count': c.count,
                  })
              .toList(),
          'byMerchant': byMerchantList
              .take(8)
              .map((m) => {
                    'merchant': m.merchant,
                    'amount': m.amount,
                    'count': m.count,
                  })
              .toList(),
          'byWeek': byWeekList
              .map((w) => {'week': w.week, 'amount': w.amount})
              .toList(),
          'budgetExec': budgetExec
              .map((b) => {
                    'categoryName': b.categoryName,
                    'used': b.used,
                    'limit': b.limit,
                  })
              .toList(),
        },
      );

      if (!mounted) return;
      setState(() {
        _income = income;
        _expense = expense;
        _byCategory = byCatList;
        _byMerchant = byMerchantList;
        _byWeek = byWeekList;
        _budgetExec = budgetExec;
        _narrative = res['narrative'] as String?;
        _highlights = (res['highlights'] as List? ?? [])
            .map((h) => _Highlight(
                  icon: (h['icon'] as String?) ?? '•',
                  text: (h['text'] as String?) ?? '',
                ))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '生成失败：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '月报',
        actions: [
          _periodToggle(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '重新生成',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _generate,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AI 正在帮你写报告…'),
                  ],
                ),
              )
            : _error != null
                ? Center(child: Text(_error!))
                : _content(),
      ),
    );
  }

  /// header 上的紧凑「上月 / 本月」切换胶囊
  Widget _periodToggle() {
    Widget seg(int v, String label) {
      final sel = _which == v;
      return GestureDetector(
        onTap: () {
          if (_which == v) return;
          setState(() => _which = v);
          _generate();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              color: sel ? AppColors.onPrimary : AppColors.text2,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg(0, '上月'), seg(1, '本月')],
        ),
      ),
    );
  }

  Widget _content() {
    final periodLabel =
        '${_periodStart.year}年${_periodStart.month}月';
    return RefreshIndicator(
      onRefresh: _generate,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部大数字
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(periodLabel,
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _bigNum('收入', _income, AppColors.income)),
                      Container(width: 1, height: 36, color: Colors.grey.shade300),
                      Expanded(child: _bigNum('支出', _expense, AppColors.expense)),
                      Container(width: 1, height: 36, color: Colors.grey.shade300),
                      Expanded(
                        child: _bigNum(
                          '结余',
                          _income - _expense,
                          (_income - _expense) >= 0
                              ? Colors.blue
                              : Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // AI 文案
          if (_narrative != null && _narrative!.isNotEmpty) ...[
            Card(
              color: Colors.deepPurple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text('🤖 ', style: TextStyle(fontSize: 16)),
                        Text(
                          'AI 点评',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _narrative!,
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_highlights.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final h in _highlights)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(h.icon, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(h.text)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 分类排行
          if (_byCategory.isNotEmpty) _sectionCard(
            title: '分类排行',
            rows: _byCategory.take(8).map((c) {
              return _BarRow(
                label: c.name,
                amount: c.amount,
                total: _expense,
                count: c.count,
              );
            }).toList(),
          ),

          // 商户排行
          if (_byMerchant.isNotEmpty) _sectionCard(
            title: '商户 Top',
            rows: _byMerchant.take(8).map((m) {
              return _BarRow(
                label: m.merchant,
                amount: m.amount,
                total: _expense,
                count: m.count,
              );
            }).toList(),
          ),

          // 预算执行
          if (_budgetExec.isNotEmpty) Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('预算执行',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  for (final b in _budgetExec)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _budgetRow(b),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _bigNum(String label, double v, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          '¥${v.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<_BarRow> rows}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _barWidget(r),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barWidget(_BarRow r) {
    final ratio = r.total > 0 ? (r.amount / r.total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(r.label, style: const TextStyle(fontSize: 13))),
            Text('${r.count}笔',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Text('¥${r.amount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        LinearProgressIndicator(
          value: ratio,
          minHeight: 4,
          backgroundColor: Colors.grey.shade100,
          valueColor: AlwaysStoppedAnimation(Colors.indigo.shade300),
        ),
      ],
    );
  }

  Widget _budgetRow(_BudgetExec b) {
    final r = b.limit > 0 ? (b.used / b.limit).clamp(0.0, 999.0) : 0.0;
    final over = r >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(b.categoryName, style: const TextStyle(fontSize: 13))),
            Text(
              '¥${b.used.toStringAsFixed(0)} / ${b.limit.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: over ? Colors.red : Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        LinearProgressIndicator(
          value: r.clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: Colors.grey.shade100,
          valueColor: AlwaysStoppedAnimation(
            over ? Colors.red : r >= 0.9 ? Colors.orange : Colors.green,
          ),
        ),
      ],
    );
  }
}

class _CatAgg {
  final String id;
  final String name;
  double amount = 0;
  int count = 0;
  _CatAgg({required this.id, required this.name});
}

class _MerchantAgg {
  final String merchant;
  double amount = 0;
  int count = 0;
  _MerchantAgg({required this.merchant});
}

class _WeekAgg {
  final String week;
  double amount = 0;
  _WeekAgg({required this.week});
}

class _BudgetExec {
  final String categoryName;
  final double used;
  final double limit;
  _BudgetExec({required this.categoryName, required this.used, required this.limit});
}

class _Highlight {
  final String icon;
  final String text;
  _Highlight({required this.icon, required this.text});
}

class _BarRow {
  final String label;
  final double amount;
  final double total;
  final int count;
  _BarRow({required this.label, required this.amount, required this.total, required this.count});
}
