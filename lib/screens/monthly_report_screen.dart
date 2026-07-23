import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/chart_kit.dart';
import '../widgets/siku_ui.dart';

/// ======================================================================
/// 月报 · 数据故事（scrollytelling）
/// ======================================================================
///
/// 通路 B：客户端解密账单本地聚合，只把脱敏汇总数字发给服务端生成
/// LLM 文案（narrative + highlights），原始 note 不出端。
///
/// 页面是一条垂直故事流，章节制：
///   01 本月总览   —— 超大支出数字（计数动画）+ 收入/结余配角
///   02 支出构成   —— 单根横向分段占比条（ChartPalette 取色）+ 图例
///   03 钱去了哪   —— 商户图标墙（首字母圆形头像，色相阶梯轮换，错峰入场）
///   04 对比与节奏 —— 对比上一周期（客户端多拉一个区间聚合）+ 周节奏条
///   05 预算执行   —— 有月预算时展示
///   06 AI 总结    —— LLM narrative + 规则层 highlights
///
/// 动效约定：每章节进入视口时 translateY(30)→0 + opacity 0→1，
/// 500ms / cubic-bezier(0.4,0,0.2,1)，只播一次；图标墙条目错峰 ~70ms；
/// 大数字随入场动画从 0 计数到目标值。颜色全部走 AppColors /
/// ChartPalette token（design_lint 强制），收入=红、支出=绿。
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

  // 本期聚合结果
  double _income = 0;
  double _expense = 0;
  List<_CatAgg> _byCategory = [];
  List<_MerchantAgg> _byMerchant = [];
  List<_WeekAgg> _byWeek = [];
  List<_BudgetExec> _budgetExec = [];

  // 上一周期总收支（对比章节；拉取失败则为 null 并隐藏该章节）
  double? _prevIncome;
  double? _prevExpense;

  // AI 生成的文案 + 关键点
  String? _narrative;
  List<_Highlight> _highlights = [];

  late DateTime _periodStart;
  late DateTime _prevPeriodStart;

  /// 章节入场动画共享的滚动控制器（_ChapterReveal 监听它触发可见性）
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 纯客户端聚合：给定区间，返回 (income, expense, byCat, byMerchant, byWeek)。
  /// 与统计页口径一致：排除转账与股票纸面盈亏。
  Future<
      ({
        double income,
        double expense,
        List<_CatAgg> byCat,
        List<_MerchantAgg> byMerchant,
        List<_WeekAgg> byWeek,
      })> _aggregate(DateTime start, DateTime end) async {
    final billsRes = await ApiService.getBills(
      startDate: DateFormat('yyyy-MM-dd').format(start),
      endDate: DateFormat('yyyy-MM-dd').format(end),
      limit: 2000,
    );
    final bills = (billsRes['bills'] as List? ?? [])
        .map((b) => Bill.fromJson(b as Map<String, dynamic>))
        .toList();

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
      final cid = b.category.id;
      final cAgg =
          byCat.putIfAbsent(cid, () => _CatAgg(id: cid, name: b.category.name));
      if (b.type == 'expense') {
        cAgg.amount += b.amount;
        cAgg.count++;
      }
      if (b.type == 'expense') {
        // 商户：取解密后 note 的第一段（· 分隔）
        final merchant = b.note.split('·').first.trim();
        if (merchant.isNotEmpty &&
            !merchant.startsWith('【') &&
            merchant.length <= 16) {
          final mAgg = byMerchant.putIfAbsent(
              merchant, () => _MerchantAgg(merchant: merchant));
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
    return (
      income: income,
      expense: expense,
      byCat: byCatList,
      byMerchant: byMerchantList,
      byWeek: byWeekList,
    );
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _narrative = null;
      _highlights = [];
      _prevIncome = null;
      _prevExpense = null;
    });
    try {
      // 1) 计算周期（本期 + 上一期，对比章节用）
      final now = DateTime.now();
      late final DateTime start;
      late final DateTime end;
      if (_which == 0) {
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0, 23, 59, 59);
      } else {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
      final prevStart = DateTime(start.year, start.month - 1, 1);
      final prevEnd = DateTime(start.year, start.month, 0, 23, 59, 59);
      _periodStart = start;
      _prevPeriodStart = prevStart;

      final user = await AuthService.getUser();
      _ledgerId = user?['currentLedgerId'] as String?;
      if (_ledgerId == null || _ledgerId!.isEmpty) {
        throw Exception('未选账本');
      }

      // 2) 本期聚合（不上传 note 明文）
      final cur = await _aggregate(start, end);

      // 3) 上一期总收支（失败不阻塞主流程，仅隐藏对比章节）
      double? prevIncome, prevExpense;
      try {
        final prev = await _aggregate(prevStart, prevEnd);
        prevIncome = prev.income;
        prevExpense = prev.expense;
      } catch (_) {}

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
                categoryName: name, used: bd.spent, limit: bd.amount));
          } else {
            // 上月：从本期分类聚合找对应分类总和
            final c = cur.byCat.firstWhere(
              (x) => x.id == (bd.categoryId ?? ''),
              orElse: () => _CatAgg(id: '', name: name),
            );
            budgetExec.add(_BudgetExec(
                categoryName: name, used: c.amount, limit: bd.amount));
          }
        }
      } catch (_) {}

      // 5) 发服务端生成叙事（只送脱敏汇总数字）
      final res = await ApiService.aiMonthlyReport(
        ledgerId: _ledgerId!,
        year: start.year,
        month: start.month,
        aggregates: {
          'income': cur.income,
          'expense': cur.expense,
          'byCategory': cur.byCat
              .take(15)
              .map((c) => {
                    'categoryId': c.id,
                    'name': c.name,
                    'amount': c.amount,
                    'count': c.count,
                  })
              .toList(),
          'byMerchant': cur.byMerchant
              .take(8)
              .map((m) => {
                    'merchant': m.merchant,
                    'amount': m.amount,
                    'count': m.count,
                  })
              .toList(),
          'byWeek': cur.byWeek
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
        _income = cur.income;
        _expense = cur.expense;
        _byCategory = cur.byCat;
        _byMerchant = cur.byMerchant;
        _byWeek = cur.byWeek;
        _budgetExec = budgetExec;
        _prevIncome = prevIncome;
        _prevExpense = prevExpense;
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

  // ── 页面骨架 ────────────────────────────────────────────────

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
                          style:
                              TextStyle(color: AppColors.text2, height: 1.5)),
                    ),
                  )
                : _story(),
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

  // ── 故事流 ──────────────────────────────────────────────────

  Widget _story() {
    final periodLabel = '${_periodStart.year}年${_periodStart.month}月';
    final hasData = _income > 0 || _expense > 0;
    return LayoutBuilder(
      builder: (context, cons) {
        return RefreshIndicator(
          onRefresh: _generate,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 64),
            children: [
              if (!hasData)
                Padding(
                  padding: EdgeInsets.only(top: cons.maxHeight * 0.3),
                  child: Center(
                    child: Text('这个周期还没有账单',
                        style: TextStyle(fontSize: 14, color: AppColors.text3)),
                  ),
                )
              else ...[
                // 01 本月总览（近一屏高，数字是主角）
                _chapter(
                  minHeight: cons.maxHeight * 0.72,
                  accent: AppColors.expense,
                  kicker: '01 · 本月总览',
                  builder: (t) => _overviewChapter(t, periodLabel),
                ),
                // 02 支出构成
                if (_byCategory.isNotEmpty)
                  _chapter(
                    accent: ChartPalette.colorAt(2),
                    kicker: '02 · 支出构成',
                    builder: _compositionChapter,
                  ),
                // 03 钱去了哪（商户图标墙）
                if (_byMerchant.isNotEmpty)
                  _chapter(
                    accent: AppColors.warning,
                    kicker: '03 · 钱去了哪',
                    builder: _merchantChapter,
                  ),
                // 04 对比与节奏
                if (_prevExpense != null || _byWeek.isNotEmpty)
                  _chapter(
                    accent: AppColors.transfer,
                    kicker: '04 · 对比与节奏',
                    builder: _compareChapter,
                  ),
                // 05 预算执行
                if (_budgetExec.isNotEmpty)
                  _chapter(
                    accent: AppColors.success,
                    kicker: '05 · 预算执行',
                    builder: _budgetChapter,
                  ),
                // 06 AI 总结
                if ((_narrative != null && _narrative!.isNotEmpty) ||
                    _highlights.isNotEmpty)
                  _chapter(
                    accent: AppColors.primary,
                    kicker: '06 · AI 总结',
                    builder: _aiChapter,
                    last: true,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 章节外壳：kicker 行（章节 accent）+ 进入视口触发的一次性入场动画。
  /// [builder] 收到 entrance 动画（0→1，已挂 ease 曲线），章节内数字 /
  /// 条目错峰都从这同一个动画派生，保证只播一次、节奏统一。
  Widget _chapter({
    required Color accent,
    required String kicker,
    required Widget Function(Animation<double> entrance) builder,
    double? minHeight,
    bool last = false,
  }) {
    return _ChapterReveal(
      controller: _scroll,
      builder: (context, t) => Container(
        constraints:
            minHeight != null ? BoxConstraints(minHeight: minHeight) : null,
        margin: EdgeInsets.only(bottom: last ? 0 : 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              minHeight != null ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  kicker,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                    color: accent,
                  ).copyWith(fontFamilyFallback: cjkFontFallback),
                ),
              ],
            ),
            const SizedBox(height: 20),
            builder(t),
          ],
        ),
      ),
    );
  }

  // ── 01 本月总览：超大支出数字 + 收入/结余配角 ────────────────

  Widget _overviewChapter(Animation<double> t, String periodLabel) {
    final balance = _income - _expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(periodLabel,
            style: TextStyle(fontSize: 13, color: AppColors.text3)),
        const SizedBox(height: 12),
        Text('总支出',
            style: TextStyle(fontSize: 15, color: AppColors.text2)),
        const SizedBox(height: 4),
        _GiantMoney(value: _expense, color: AppColors.text1, entrance: t),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
                child: _miniStat('收入', _income, AppColors.income, t,
                    delay: 0.25)),
            Expanded(
                child: _miniStat(
                    '结余',
                    balance,
                    balance >= 0 ? AppColors.success : AppColors.danger,
                    t,
                    delay: 0.4)),
            Expanded(
                child: _miniStat(
                    '支出笔数',
                    _byCategory
                        .fold<int>(0, (s, c) => s + c.count)
                        .toDouble(), // 分类聚合只计支出笔数
                    AppColors.text1,
                    t,
                    delay: 0.55,
                    money: false,
                    suffix: ' 笔')),
          ],
        ),
      ],
    );
  }

  /// 配角统计：小号计数数字 + 标签。
  Widget _miniStat(String label, double value, Color color,
      Animation<double> entrance,
      {double delay = 0, bool money = true, String suffix = ''}) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: Interval(delay.clamp(0.0, 0.8), 1, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final v = value * anim.value;
        final text = money
            ? '¥${NumberFormat('#,###').format(v.round())}'
            : '${v.round()}$suffix';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 4),
            Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w400,
                color: color,
              ).copyWith(fontFamilyFallback: cjkFontFallback),
            ),
          ],
        );
      },
    );
  }

  // ── 02 支出构成：单根横向分段占比条 + 图例 ───────────────────

  Widget _compositionChapter(Animation<double> t) {
    // Top 6 + 其他，保证分段条可读
    final top = _byCategory.take(6).toList();
    final restAmount =
        _byCategory.skip(6).fold<double>(0, (s, c) => s + c.amount);
    final segs = <({String name, double amount, int count, Color color})>[
      for (var i = 0; i < top.length; i++)
        (
          name: top[i].name,
          amount: top[i].amount,
          count: top[i].count,
          color: ChartPalette.colorAt(i),
        ),
      if (restAmount > 0)
        (
          name: '其他',
          amount: restAmount,
          count: _byCategory.skip(6).fold<int>(0, (s, c) => s + c.count),
          color: ChartPalette.colorAt(5), // 中性灰绿固定给「其他」
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SegmentBar(segments: segs, total: _expense, entrance: t),
        const SizedBox(height: 24),
        for (var i = 0; i < segs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: segs[i].color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(segs[i].name,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 14, color: AppColors.text1)),
                ),
                Text(
                  _expense > 0
                      ? '${(segs[i].amount / _expense * 100).toStringAsFixed(0)}%'
                      : '0%',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(width: 12),
                AmountText(segs[i].amount,
                    size: AmountSize.aux,
                    tone: AmountTone.expense,
                    decimals: 0),
              ],
            ),
          ),
      ],
    );
  }

  // ── 03 钱去了哪：商户图标墙 ─────────────────────────────────

  Widget _merchantChapter(Animation<double> t) {
    final top = _byMerchant.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最常花钱的 ${top.length} 个去处',
            style: TextStyle(fontSize: 13, color: AppColors.text3)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 18,
          runSpacing: 20,
          children: [
            for (var i = 0; i < top.length; i++)
              _MerchantAvatar(
                agg: top[i],
                index: i,
                // 错峰 70ms 等效：把入场动画切成小区间
                entrance: CurvedAnimation(
                  parent: t,
                  curve: Interval((i * 0.07).clamp(0.0, 0.75), 1,
                      curve: Curves.easeOut),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── 04 对比与节奏：对比上一周期 + 周节奏 ────────────────────

  Widget _compareChapter(Animation<double> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_prevExpense != null) ...[
          Text('支出较上一周期',
              style: TextStyle(fontSize: 13, color: AppColors.text3)),
          const SizedBox(height: 8),
          _DeltaNumber(
            current: _expense,
            previous: _prevExpense!,
            entrance: t,
          ),
          const SizedBox(height: 6),
          Text(
            '${_prevPeriodStart.month}月 ¥${NumberFormat('#,###').format(_prevExpense!.round())}'
            ' → ${_periodStart.month}月 ¥${NumberFormat('#,###').format(_expense.round())}',
            style: TextStyle(fontSize: 13, color: AppColors.text3),
          ),
          if (_prevIncome != null && _prevIncome! > 0) ...[
            const SizedBox(height: 16),
            Text(
              '收入：${_prevPeriodStart.month}月 ¥${NumberFormat('#,###').format(_prevIncome!.round())}'
              ' → ${_periodStart.month}月 ¥${NumberFormat('#,###').format(_income.round())}',
              style: TextStyle(fontSize: 13, color: AppColors.text3),
            ),
          ],
        ],
        if (_byWeek.isNotEmpty) ...[
          SizedBox(height: _prevExpense != null ? 36 : 0),
          Text('本月节奏', style: TextStyle(fontSize: 13, color: AppColors.text3)),
          const SizedBox(height: 16),
          _WeekRhythm(weeks: _byWeek, entrance: t),
        ],
      ],
    );
  }

  // ── 05 预算执行 ────────────────────────────────────────────

  Widget _budgetChapter(Animation<double> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in _budgetExec)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _budgetRow(b),
          ),
      ],
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
                  style: TextStyle(fontSize: 14, color: AppColors.text1)),
            ),
            AmountText(b.used,
                size: AmountSize.aux,
                decimals: 0,
                color: over ? AppColors.danger : AppColors.text1),
            Text(' / ',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            AmountText(b.limit,
                size: AmountSize.aux, decimals: 0, color: AppColors.text3),
          ],
        ),
        const SizedBox(height: 6),
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

  // ── 06 AI 总结：narrative + highlights ─────────────────────

  Widget _aiChapter(Animation<double> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_narrative != null && _narrative!.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('司库说',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _narrative!,
            style: TextStyle(fontSize: 16, height: 1.8, color: AppColors.text1),
          ),
        ],
        if (_highlights.isNotEmpty) ...[
          const SizedBox(height: 24),
          for (var i = 0; i < _highlights.length; i++)
            _staggered(
              t,
              i,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_highlights[i].icon,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_highlights[i].text,
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.text2)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 章节内条目错峰工具：把共享 entrance 动画切成第 i 段小区间。
  Widget _staggered(Animation<double> entrance, int i, Widget child) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve:
          Interval((i * 0.12).clamp(0.0, 0.7), 1, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }
}

// ======================================================================
// 组件
// ======================================================================

/// 章节入场容器：进入视口（顶边越过视口 88% 线）时触发一次
/// translateY(30)→0 + opacity 0→1，500ms / cubic-bezier(0.4,0,0.2,1)。
class _ChapterReveal extends StatefulWidget {
  const _ChapterReveal({required this.controller, required this.builder});

  final ScrollController controller;
  final Widget Function(BuildContext context, Animation<double> entrance)
      builder;

  @override
  State<_ChapterReveal> createState() => _ChapterRevealState();
}

class _ChapterRevealState extends State<_ChapterReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _entrance;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _entrance = CurvedAnimation(
        parent: _ctl, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    widget.controller.addListener(_check);
  }

  void _check() {
    if (_triggered || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final dy = box.localToGlobal(Offset.zero).dy;
    final vh = MediaQuery.of(context).size.height;
    if (dy < vh * 0.88) {
      _triggered = true;
      widget.controller.removeListener(_check);
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        child: Transform.translate(
          offset: Offset(0, 30 * (1 - _entrance.value)),
          child: child,
        ),
      ),
      child: Builder(builder: (context) => widget.builder(context, _entrance)),
    );
  }
}

/// 超大金额数字：FittedBox 适配小屏，字重 Light 靠尺寸制造层级，
/// 随入场动画从 0 计数到目标值。
class _GiantMoney extends StatelessWidget {
  const _GiantMoney(
      {required this.value, required this.color, required this.entrance});

  final double value;
  final Color color;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: const Interval(0.15, 1, curve: Curves.easeOut),
    );
    return SizedBox(
      height: 100,
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: anim,
          builder: (_, __) => Text(
            '¥${NumberFormat('#,###').format((value * anim.value).round())}',
            style: GoogleFonts.outfit(
              fontSize: 88,
              fontWeight: FontWeight.w300,
              letterSpacing: -3,
              height: 1.0,
              color: color,
            ).copyWith(fontFamilyFallback: cjkFontFallback),
          ),
        ),
      ),
    );
  }
}

/// 对比增量数字：大字号百分比 + 涨跌语义（支出降=success / 升=warning）。
class _DeltaNumber extends StatelessWidget {
  const _DeltaNumber(
      {required this.current,
      required this.previous,
      required this.entrance});

  final double current;
  final double previous;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: const Interval(0.15, 1, curve: Curves.easeOut),
    );
    final ratio = previous > 0 ? (current - previous) / previous : 0.0;
    final down = ratio <= 0;
    final color = down ? AppColors.success : AppColors.warning;
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final shown = ratio.abs() * 100 * anim.value;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(
              down
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 34,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              '${shown.toStringAsFixed(0)}%',
              style: GoogleFonts.outfit(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                letterSpacing: -1.5,
                height: 1.0,
                color: color,
              ).copyWith(fontFamilyFallback: cjkFontFallback),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(down ? '省了' : '多了',
                  style: TextStyle(fontSize: 14, color: AppColors.text3)),
            ),
          ],
        );
      },
    );
  }
}

/// 分段式占比条：一根横向条，每段一个色、宽度=占比（ChartPalette 取色）。
/// 段宽随入场动画从 0 长到目标占比。
class _SegmentBar extends StatelessWidget {
  const _SegmentBar(
      {required this.segments, required this.total, required this.entrance});

  final List<({String name, double amount, int count, Color color})> segments;
  final double total;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: const Interval(0.1, 1, curve: Curves.easeOut),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 16,
        child: AnimatedBuilder(
          animation: anim,
          builder: (_, __) => Row(
            children: [
              for (var i = 0; i < segments.length; i++)
                Expanded(
                  flex: total > 0
                      ? ((segments[i].amount / total) *
                              1000 *
                              anim.value)
                          .round()
                          .clamp(1, 1000)
                          .toInt()
                      : 1,
                  child: Container(color: segments[i].color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 商户图标墙条目：圆形首字母头像（色相阶梯轮换的语义色底）+ 名称 + 金额。
/// 颜色全部从 AppColors 语义色派生（HSL 色相平移），无硬编码色值。
class _MerchantAvatar extends StatelessWidget {
  const _MerchantAvatar(
      {required this.agg, required this.index, required this.entrance});

  final _MerchantAgg agg;
  final int index;
  final Animation<double> entrance;

  /// 语义色底轮换：基准色取 AppColors 语义族，同一族内按轮次做色相阶梯。
  static Color _avatarColor(int i) {
    final bases = [
      AppColors.expense,
      AppColors.income,
      AppColors.warning,
      AppColors.success,
      AppColors.primary,
      AppColors.transfer,
    ];
    final base = bases[i % bases.length];
    final hsl = HSLColor.fromColor(base);
    final hue = (hsl.hue + (i ~/ bases.length) * 28) % 360;
    return hsl.withHue(hue).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final c = _avatarColor(index);
    return AnimatedBuilder(
      animation: entrance,
      builder: (_, __) => Opacity(
        opacity: entrance.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - entrance.value)),
          child: SizedBox(
            width: 68,
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: c.withValues(alpha: 0.4), width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    agg.merchant.characters.first,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: c,
                    ).copyWith(fontFamilyFallback: cjkFontFallback),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  agg.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.text2),
                ),
                Text(
                  '¥${NumberFormat('#,###').format(agg.amount.round())}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text1,
                  ).copyWith(fontFamilyFallback: cjkFontFallback),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 周节奏：几根矮柱（自绘 Container 条），一眼看出钱花在哪几周。
class _WeekRhythm extends StatelessWidget {
  const _WeekRhythm({required this.weeks, required this.entrance});

  final List<_WeekAgg> weeks;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final maxV = weeks.fold<double>(0, (m, w) => w.amount > m ? w.amount : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < weeks.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _staggeredBar(i, maxV),
            ),
          ),
      ],
    );
  }

  Widget _staggeredBar(int i, double maxV) {
    final anim = CurvedAnimation(
      parent: entrance,
      curve: Interval((i * 0.1).clamp(0.0, 0.7), 1, curve: Curves.easeOut),
    );
    final share = maxV > 0 ? weeks[i].amount / maxV : 0.0;
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Column(
        children: [
          Text(
            '¥${NumberFormat('#,###').format((weeks[i].amount * anim.value).round())}',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ).copyWith(fontFamilyFallback: cjkFontFallback),
          ),
          const SizedBox(height: 6),
          Container(
            height: 8 + 48 * share * anim.value,
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(
                  alpha: 0.35 + 0.65 * share * anim.value),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Text(weeks[i].week,
              style: TextStyle(fontSize: 11, color: AppColors.text3)),
        ],
      ),
    );
  }
}

// ======================================================================
// 数据类
// ======================================================================

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
  _BudgetExec(
      {required this.categoryName, required this.used, required this.limit});
}

class _Highlight {
  final String icon;
  final String text;
  _Highlight({required this.icon, required this.text});
}
