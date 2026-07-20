import 'package:flutter/material.dart';
import '../widgets/siku_ui.dart';
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
  List<_BudgetExec> _budgetExec = [];

  // AI 生成的文案 + 关键点
  String? _narrative;
  List<_Highlight> _highlights = [];

  late DateTime _periodStart;

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
        // 转账（账户互转）与股票纸面盈亏不计收支（与统计口径一致）
        if (b.isTransfer || b.source == 'stock') continue;
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
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text('AI 正在帮你写报告…',
                        style: TextStyle(color: AppColors.text2)),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.text2, height: 1.5)),
                    ),
                  )
                : _content(),
      ),
    );
  }

  /// header 上的紧凑「上月 / 本月」切换
  Widget _periodToggle() {
    return AuraSegmented<int>(
      options: const [
        (value: 0, label: '上月'),
        (value: 1, label: '本月'),
      ],
      selected: _which,
      expanded: false,
      onChanged: (v) {
        if (_which == v) return;
        setState(() => _which = v);
        _generate();
      },
    );
  }

  Widget _content() {
    final periodLabel = '${_periodStart.year}年${_periodStart.month}月';
    return RefreshIndicator(
      onRefresh: _generate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          // 顶部大数字
          _summaryCard(periodLabel),
          const SizedBox(height: 12),

          // AI 文案
          if (_narrative != null && _narrative!.isNotEmpty) ...[
            _aiCard(),
            const SizedBox(height: 12),
          ],

          if (_highlights.isNotEmpty) ...[
            _highlightsCard(),
            const SizedBox(height: 12),
          ],

          // 分类排行
          if (_byCategory.isNotEmpty) ...[
            _sectionCard(
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
            const SizedBox(height: 12),
          ],

          // 商户排行
          if (_byMerchant.isNotEmpty) ...[
            _sectionCard(
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
            const SizedBox(height: 12),
          ],

          // 预算执行
          if (_budgetExec.isNotEmpty) _budgetCard(),
        ],
      ),
    );
  }

  // ── 顶部汇总卡：收入 / 支出 / 结余 三大数字 ─────────────────
  Widget _summaryCard(String periodLabel) {
    final balance = _income - _expense;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(periodLabel,
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _bigNum('收入', _income, AmountTone.income)),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _bigNum('支出', _expense, AmountTone.expense)),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _bigNum('结余', balance, AmountTone.auto)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigNum(String label, double v, AmountTone tone) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.text3)),
        const SizedBox(height: 4),
        AmountText(v, size: AmountSize.card, tone: tone, decimals: 0),
      ],
    );
  }

  // ── AI 点评：info 级洞察 —— surface 底 + 左侧 3px primary 色条 ──
  Widget _aiCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppTheme.ambientShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      // Stack + 左侧贴边色条：高度跟随内容（同 home_screen 的 _insightCard）
      child: Stack(
        children: [
          Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: AppColors.primary)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'AI 点评',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _narrative!,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.6, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── AI 关键点列表 ─────────────────────────────────────────
  Widget _highlightsCard() {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        children: [
          for (final h in _highlights)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Text(h.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(h.text,
                        style: TextStyle(
                            fontSize: 13, height: 1.4,
                            color: AppColors.text1)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 排行卡（分类 / 商户通用）：标题 + 进度条行 ──────────────
  Widget _sectionCard({required String title, required List<_BarRow> rows}) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _barWidget(r),
            ),
        ],
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
            Expanded(
              child: Text(r.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.text1)),
            ),
            Text('${r.count}笔',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
            const SizedBox(width: 10),
            // 排行全是支出金额，统一 expense 语义色
            AmountText(r.amount,
                size: AmountSize.aux, tone: AmountTone.expense, decimals: 0),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }

  // ── 预算执行卡 ────────────────────────────────────────────
  Widget _budgetCard() {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('预算执行',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 8),
          for (final b in _budgetExec)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _budgetRow(b),
            ),
        ],
      ),
    );
  }

  Widget _budgetRow(_BudgetExec b) {
    final r = b.limit > 0 ? (b.used / b.limit).clamp(0.0, 999.0) : 0.0;
    final over = r >= 1;
    // 语义填色：超支 danger · 临界 warning · 节约 expense · 正常 primary
    final fill = over
        ? AppColors.danger
        : r >= 0.9
            ? AppColors.warning
            : r < 0.6
                ? AppColors.expense
                : AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(b.categoryName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.text1)),
            ),
            AmountText(b.used,
                size: AmountSize.aux,
                decimals: 0,
                color: over ? AppColors.danger : AppColors.text1),
            Text(' / ', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            AmountText(b.limit,
                size: AmountSize.aux, decimals: 0, color: AppColors.text3),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: r.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(fill),
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
