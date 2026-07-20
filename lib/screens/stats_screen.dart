import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../models/bill.dart';
import '../widgets/chart_kit.dart';
import '../widgets/siku_ui.dart';
import 'add_bill_screen.dart';
import 'bills_screen.dart';
import 'tools/stock_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

enum _Period { month, year }

class _StatsScreenState extends State<StatsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  _Period _period = _Period.month;
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);
  double _totalIncome = 0;
  double _prevIncome = 0; // 上一期（环比基准）
  double _prevExpense = 0;
  Map<String, double> _prevCatTotal = {}; // 上一期各分类合计（by id）
  double _totalExpense = 0;
  List<_CatStat> _expenseStats = [];
  List<_CatStat> _incomeStats = [];
  bool _loading = true;
  int _tab = 0; // 0 = expense, 1 = income

  // pie touch
  int _touchedIndex = -1;

  // Asset summary + trend
  double _assetTotal  = 0;
  double _assetMine   = 0;
  double _assetShared = 0;
  double _assetOthers = 0;
  double _receivable  = 0; // 债权：借出未收回
  double _payable     = 0; // 负债：借入未还
  double _netWorth    = 0; // 净资产 = 账户余额 + 债权 − 负债
  List<_AssetPoint> _assetTrend = [];

  // 多人账本：按记账人聚合
  List<_MemberStat> _memberStats = [];

  // 股票持仓（统计卡片用，仅 held=true；与股票页同一接口/口径）
  List<Map<String, dynamic>> _stockHoldings = [];

  @override
  void initState() {
    super.initState();
    refreshBus.addListener(_onBump);
    _load();
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onBump);
    super.dispose();
  }

  void _onBump() {
    if (mounted) _load();
  }

  /// 跳到账单页并按当前周期 + 点击维度预选过滤（对账用）
  void _openBills({String? type, String? userId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillsScreen(
          isTab: false,
          initialType: type,
          initialUserIds: userId != null ? [userId] : null,
          initialRangeStart: DateTime.parse(_startDate),
          initialRangeEnd: DateTime.parse(_endDate),
        ),
      ),
    );
  }

  String get _startDate {
    if (_period == _Period.year) return '${_anchor.year}-01-01';
    return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-01';
  }

  String get _endDate {
    if (_period == _Period.year) return '${_anchor.year}-12-31';
    final last = DateTime(_anchor.year, _anchor.month + 1, 0).day;
    return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
  }

  /// 上一期（环比基准）：月视图=上月，年视图=去年
  DateTime get _prevAnchor => _period == _Period.year
      ? DateTime(_anchor.year - 1, 1)
      : DateTime(_anchor.year, _anchor.month - 1);

  String get _prevStartDate {
    final p = _prevAnchor;
    if (_period == _Period.year) return '${p.year}-01-01';
    return '${p.year}-${p.month.toString().padLeft(2, '0')}-01';
  }

  String get _prevEndDate {
    final p = _prevAnchor;
    if (_period == _Period.year) return '${p.year}-12-31';
    final last = DateTime(p.year, p.month + 1, 0).day;
    return '${p.year}-${p.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
  }

  String get _periodLabel {
    if (_period == _Period.year) return '${_anchor.year}年';
    return DateFormat('yyyy年M月').format(_anchor);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 当前期 + 上一期并行拉，供环比对比；上一期失败不影响主数据
      final results = await Future.wait([
        ApiService.getStats(startDate: _startDate, endDate: _endDate),
        ApiService.getStats(startDate: _prevStartDate, endDate: _prevEndDate)
            .catchError((_) => <String, dynamic>{}),
      ]);
      final res = results[0];
      final prevRes = results[1];
      if (!mounted) return;
      final prevSum = (prevRes['summary'] as Map?) ?? {};
      final prevCats = <String, double>{};
      for (final e in (prevRes['categoryStats'] as List? ?? [])) {
        final m = e as Map<String, dynamic>;
        prevCats[m['id'] as String? ?? ''] =
            (m['total'] as num?)?.toDouble() ?? 0;
      }
      final sum = (res['summary'] as Map?) ?? {};
      final rawStats = (res['categoryStats'] as List? ?? [])
          .map((e) => _CatStat.fromJson(e as Map<String, dynamic>))
          .toList();
      final asset = (res['assetSummary'] as Map?) ?? {};
      final trendRaw = (res['assetTrend'] as List? ?? []);
      setState(() {
        _prevIncome = (prevSum['totalIncome'] as num?)?.toDouble() ?? 0;
        _prevExpense = (prevSum['totalExpense'] as num?)?.toDouble() ?? 0;
        _prevCatTotal = prevCats;
        _totalIncome = (sum['totalIncome'] as num?)?.toDouble() ?? 0;
        _totalExpense = (sum['totalExpense'] as num?)?.toDouble() ?? 0;
        _expenseStats =
            rawStats.where((s) => s.type == 'expense').toList()
              ..sort((a, b) => b.total.compareTo(a.total));
        _incomeStats =
            rawStats.where((s) => s.type == 'income').toList()
              ..sort((a, b) => b.total.compareTo(a.total));
        _assetTotal = (asset['total'] as num?)?.toDouble() ?? 0;
        _assetMine = (asset['mine'] as num?)?.toDouble() ?? 0;
        _assetShared = (asset['shared'] as num?)?.toDouble() ?? 0;
        _assetOthers = (asset['others'] as num?)?.toDouble() ?? 0;
        _receivable = (asset['receivable'] as num?)?.toDouble() ?? 0;
        _payable = (asset['payable'] as num?)?.toDouble() ?? 0;
        _netWorth = (asset['netWorth'] as num?)?.toDouble() ?? _assetTotal;
        _assetTrend = trendRaw
            .map((p) => _AssetPoint.fromJson(p as Map<String, dynamic>))
            .toList();
        _memberStats = ((res['memberStats'] as List?) ?? [])
            .map((m) => _MemberStat.fromJson(m as Map<String, dynamic>))
            .toList();
        _loading = false;
        _touchedIndex = -1;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // 股票持仓（best-effort，不阻塞主统计；无持仓则卡片不显示）
    ApiService.getStocks().then((list) {
      if (!mounted) return;
      setState(() {
        _stockHoldings = list
            .map((e) => (e as Map).cast<String, dynamic>())
            .where((s) => s['held'] == true)
            .toList();
      });
    }).catchError((_) {});
  }

  void _prev() {
    setState(() {
      if (_period == _Period.year) {
        _anchor = DateTime(_anchor.year - 1, 1);
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month - 1);
      }
    });
    _load();
  }

  void _next() {
    if (!_canGoNext) return;
    setState(() {
      if (_period == _Period.year) {
        _anchor = DateTime(_anchor.year + 1, 1);
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + 1);
      }
    });
    _load();
  }

  bool get _canGoNext {
    final now = DateTime.now();
    if (_period == _Period.year) return _anchor.year < now.year;
    return _anchor.isBefore(DateTime(now.year, now.month));
  }

  void _switchPeriod(_Period p) {
    if (_period == p) return;
    setState(() {
      _period = p;
      // 切到年度时，把 anchor 对齐到当年 1 月；切回月度时，对齐到当月
      final now = DateTime.now();
      if (p == _Period.year) {
        _anchor = DateTime(_anchor.year, 1);
      } else {
        // 如果还在当前年，对齐到当前月；否则对齐到该年最后一个月
        _anchor = (_anchor.year == now.year)
            ? DateTime(now.year, now.month)
            : DateTime(_anchor.year, 12);
      }
    });
    _load();
  }

  List<_CatStat> get _currentStats =>
      _tab == 0 ? _expenseStats : _incomeStats;
  double get _currentTotal => _tab == 0 ? _totalExpense : _totalIncome;

  // ── Pie colours ───────────────────────────────────────────────
  // 切片 / 图例 / 占比条统一走 ChartPalette（见 widgets/chart_kit.dart 规范），
  // 用同一 index 取色保证三者一致。

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AuraAppBar(
        title: '统计',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _periodToggle()),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _dateNav(),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _assetCard(),
                    const SizedBox(height: 16),
                    _summaryRow(),
                    if (_stockHoldings.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _stockCard(),
                    ],
                    if (_memberStats.length >= 2) ...[
                      const SizedBox(height: 16),
                      _memberCard(),
                    ],
                    const SizedBox(height: 16),
                    _tabBar(),
                    const SizedBox(height: 16),
                    if (_currentStats.isEmpty)
                      _empty()
                    else ...[
                      _pieCard(),
                      const SizedBox(height: 16),
                      _categoryList(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ── Period toggle (月 / 年) ─────────────────────────────────
  Widget _periodToggle() {
    return AuraSegmented<_Period>(
      options: const [
        (value: _Period.month, label: '月'),
        (value: _Period.year, label: '年'),
      ],
      selected: _period,
      onChanged: _switchPeriod,
      expanded: false,
    );
  }

  // ── Date navigator ────────────────────────────────────────────
  Widget _dateNav() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(children: [
          _navArrow(Icons.chevron_left_rounded, _prev, enabled: true),
          Expanded(
            child: Text(
              _periodLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1),
            ),
          ),
          _navArrow(Icons.chevron_right_rounded,
              _canGoNext ? _next : null,
              enabled: _canGoNext),
        ]),
      );

  /// 紧凑的左右翻页按钮（36×36），避免 IconButton 默认 48 高撑破 header bottom
  Widget _navArrow(IconData icon, VoidCallback? onTap, {required bool enabled}) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon,
            size: 24,
            color: enabled ? AppColors.text2 : AppColors.border),
      ),
    );
  }

  // ── Asset card（净资产 + 拆解 + 走势线图） ─────────────────
  Widget _assetCard() {
    final hasShared = _assetShared.abs() > 0.01;
    final hasOthers = _assetOthers.abs() > 0.01;
    final isFamily = hasShared || hasOthers;
    // 有借贷往来时标题升级为「净资产」，并展示 可动用/债权/负债 拆解
    final hasLoans = _receivable > 0.009 || _payable > 0.009;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(hasLoans ? '净资产' : (isFamily ? '家庭总资产' : '总资产'),
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const Spacer(),
            Text(_periodLabel,
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          const SizedBox(height: 4),
          AmountText(hasLoans ? _netWorth : _assetTotal,
              size: AmountSize.hero, color: AppColors.text1),
          if (hasLoans) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 14, runSpacing: 4, children: [
              _netWorthKv('可动用', fmtMoney(_assetTotal), AppColors.text2),
              if (_receivable > 0.009)
                _netWorthKv(
                    '债权', '+${fmtMoney(_receivable)}', AppColors.income),
              if (_payable > 0.009)
                _netWorthKv(
                    '负债', '-${fmtMoney(_payable)}', AppColors.expense),
            ]),
          ],
          if (isFamily) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _assetMiniStat('我的', _assetMine, 1.0),
              if (hasShared) _assetMiniStat('共享', _assetShared, 0.55),
              if (hasOthers) _assetMiniStat('其他成员', _assetOthers, 0.28),
            ]),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: _assetTrend.length < 2
                ? Center(
                    child: Text(
                      '账单数据不足，无法生成趋势图',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text3),
                    ),
                  )
                : _trendChart(),
          ),
        ],
      ),
    );
  }

  Widget _netWorthKv(String label, String value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.text3)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ],
      );

  Widget _assetMiniStat(String label, double value, double dotOpacity) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: dotOpacity),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text('$label ${fmtMoneyInt(value)}',
              style: TextStyle(fontSize: 11, color: AppColors.text2)),
        ],
      );

  Widget _trendChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _assetTrend.length; i++) {
      spots.add(FlSpot(i.toDouble(), _assetTrend[i].balance));
    }
    final values = _assetTrend.map((p) => p.balance).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.15 + 1;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: auraGrid(),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (_assetTrend.length / 4).clamp(1, 9999).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= _assetTrend.length) return const SizedBox();
                final p = _assetTrend[i];
                // 月度 → 显示 M/d；年度 → 显示 M月
                final label = _period == _Period.year
                    ? '${p.date.substring(5, 7)}月'
                    : p.date.substring(5).replaceFirst('-', '/');
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 10, color: AppColors.text3)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: auraLineTooltipData(
            getTooltipItems: (items) => items.map((it) {
              final idx = it.x.toInt();
              final date = _assetTrend[idx].date;
              return LineTooltipItem(
                '$date\n${fmtMoney(it.y)}',
                auraTooltipStyle().textStyle,
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppColors.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary row ───────────────────────────────────────────────
  Widget _summaryRow() => Row(children: [
        _summaryCard('收入', _totalIncome, AppColors.income,
            AppColors.incomeLight, prev: _prevIncome,
            onTap: () => _openBills(type: 'income')),
        const SizedBox(width: 10),
        _summaryCard('支出', _totalExpense, AppColors.expense,
            AppColors.expenseLight, prev: _prevExpense,
            onTap: () => _openBills(type: 'expense')),
        const SizedBox(width: 10),
        _summaryCard('结余', _totalIncome - _totalExpense,
            AppColors.primary, AppColors.primaryLight,
            prev: _prevIncome - _prevExpense,
            onTap: () => _openBills()),
      ]);

  /// 环比文案：上一期为 0/负基准时不给百分比（没意义）
  String? _momText(double cur, double prev) {
    if (prev.abs() < 0.01) return cur.abs() < 0.01 ? null : '上期 ¥0';
    final pct = (cur - prev) / prev.abs() * 100;
    if (pct.abs() < 0.5) return '与上期持平';
    return '比上期${pct > 0 ? '↑' : '↓'}${pct.abs().toStringAsFixed(0)}%';
  }

  Widget _summaryCard(
      String label, double amount, Color color, Color bg,
      {double? prev, VoidCallback? onTap}) {
    final mom = prev != null ? _momText(amount, prev) : null;
    return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, size: 14, color: color),
              ]),
              const SizedBox(height: 6),
              AmountText(
                amount.abs(),
                size: AmountSize.card,
                decimals: 0,
                color: color,
              ),
              if (mom != null) ...[
                const SizedBox(height: 3),
                Text(mom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: AppColors.text2)),
              ],
            ]),
          ),
        ),
      );
  }

  // ── 股票持仓卡：市值/当日盈亏/总盈亏（口径与股票页一致），点击进股票页 ──
  Widget _stockCard() {
    double cost = 0, mv = 0, todayPnl = 0;
    var hasToday = false;
    for (final s in _stockHoldings) {
      final bp = (s['buyPrice'] as num?)?.toDouble();
      final sh = (s['shares'] as num?)?.toDouble();
      final pr = (s['price'] as num?)?.toDouble();
      if (bp == null || sh == null || pr == null || bp <= 0 || sh <= 0) {
        continue;
      }
      cost += bp * sh;
      mv += pr * sh;
      final ch = (s['change'] as num?)?.toDouble();
      if (ch != null) {
        todayPnl += ch * sh;
        hasToday = true;
      }
    }
    final pl = mv - cost;
    final plPct = cost > 0 ? pl / cost * 100 : 0.0;
    final plColor = pl >= 0 ? AppColors.income : AppColors.expense;
    final todayColor = todayPnl >= 0 ? AppColors.income : AppColors.expense;

    return GlassCard(
      radius: 16,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StockScreen()),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Text('📈', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('股票持仓 · ${_stockHoldings.length} 只',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text('市值 ${fmtMoney(mv)}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (hasToday)
            Text('今日 ${todayPnl >= 0 ? '+' : ''}${fmtMoney(todayPnl)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: todayColor)),
          const SizedBox(height: 2),
          Text(
            '总盈亏 ${pl >= 0 ? '+' : ''}${fmtMoney(pl)}'
            '（${pl >= 0 ? '+' : ''}${plPct.toStringAsFixed(1)}%）',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: plColor),
          ),
        ]),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
      ]),
    );
  }

  // ── Member breakdown card（按记账人统计） ─────────────────
  Widget _memberCard() {
    final totalIncome = _memberStats.fold<double>(0, (s, m) => s + m.income);
    final totalExpense = _memberStats.fold<double>(0, (s, m) => s + m.expense);
    final maxAmount = _memberStats
        .map((m) => m.income + m.expense)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.groups_rounded,
                size: 16, color: AppColors.text2),
            const SizedBox(width: 6),
            Text('按记账人',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const Spacer(),
            Text(
                '共 ${_memberStats.length} 人 · ${_memberStats.fold<int>(0, (s, m) => s + m.count)} 笔',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          const SizedBox(height: 12),
          ..._memberStats.map((m) => _memberRow(
                m,
                maxAmount: maxAmount,
                isLast: m == _memberStats.last,
              )),
          if (_memberStats.length > 1) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Text('合计',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                if (totalIncome > 0) ...[
                  Text('+${fmtMoneyInt(totalIncome)}  ',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.income,
                          fontWeight: FontWeight.w600)),
                ],
                if (totalExpense > 0)
                  Text('-${fmtMoneyInt(totalExpense)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.expense,
                          fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberRow(_MemberStat m,
      {required double maxAmount, required bool isLast}) {
    final pct = maxAmount > 0 ? (m.income + m.expense) / maxAmount : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openBills(userId: m.userId),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: AppColors.primary,
              child: Text(
                m.displayName.isEmpty
                    ? '?'
                    : m.displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(m.displayName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1),
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${m.count} 笔',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
            Icon(Icons.chevron_right_rounded,
                size: 14, color: AppColors.text3),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.surfaceAlt,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            if (m.income > 0) ...[
              Text('收入 ',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.text2)),
              Text('+${fmtMoney(m.income)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.income,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
            ],
            if (m.expense > 0) ...[
              Text('支出 ',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.text2)),
              Text('-${fmtMoney(m.expense)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.expense,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ],
        ),
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────
  Widget _tabBar() => AuraSegmented<int>(
        options: const [
          (value: 0, label: '支出'),
          (value: 1, label: '收入'),
        ],
        selected: _tab,
        onChanged: (i) => setState(() {
          _tab = i;
          _touchedIndex = -1;
        }),
      );

  // ── Pie chart card ────────────────────────────────────────────
  Widget _pieCard() {
    final stats = _currentStats;
    final total = _currentTotal;

    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex = pieTouchResponse
                          .touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sections: stats.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  final pct = total > 0 ? s.total / total * 100 : 0;
                  final touched = _touchedIndex == i;
                  return PieChartSectionData(
                    value: s.total,
                    color: ChartPalette.colorAt(i),
                    radius: touched ? 54 : 46,
                    title: touched
                        ? '${pct.toStringAsFixed(1)}%'
                        : '',
                    titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white), // design:ok 彩色切片上的标签
                  );
                }).toList(),
                centerSpaceRadius: 28,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: stats.take(5).toList().asMap().entries.map((e) {
                final i = e.key;
                final s = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ChartPalette.colorAt(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(s.icon ?? '📂',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(s.name,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text2),
                          overflow: TextOverflow.ellipsis),
                    ),
                    AmountText(
                      s.total,
                      size: AmountSize.aux,
                      decimals: 0,
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category list ─────────────────────────────────────────────
  /// 分类行的环比小注：" · 比上期↑23%" / " · 新增"；变化<1% 或无基准则空
  String _catMomText(_CatStat s) {
    final prev = _prevCatTotal[s.id];
    if (prev == null || prev < 0.01) {
      return _prevCatTotal.isEmpty ? '' : ' · 新增';
    }
    final pct = (s.total - prev) / prev * 100;
    if (pct.abs() < 1) return '';
    return ' · 比上期${pct > 0 ? '↑' : '↓'}${pct.abs().toStringAsFixed(0)}%';
  }

  Widget _categoryList() {
    final stats = _currentStats;
    final total = _currentTotal > 0 ? _currentTotal : 1;

    return GlassCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        children: stats.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final pct = s.total / total;
          final isLast = i == stats.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: () => _showCategoryBills(s),
                child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Row(children: [
                      Text(s.icon ?? '📂',
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(s.name,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.text1)),
                              const Spacer(),
                              AmountText(s.total,
                                  size: AmountSize.list,
                                  tone: _tab == 0
                                      ? AmountTone.expense
                                      : AmountTone.income),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Text('${s.count}笔${_catMomText(s)}',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.text2)),
                              const Spacer(),
                              Text('${(pct * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.text2)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: AppColors.text3),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            ChartPalette.colorAt(i)),
                      ),
                    ),
                  ],
                ),
                ),
              ),
              if (!isLast) const Divider(height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 点分类 → 弹出该分类在当前周期里的具体账单
  void _showCategoryBills(_CatStat s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryBillsSheet(
        categoryId: s.id,
        type: s.type,
        name: s.name,
        icon: s.icon ?? '📂',
        total: s.total,
        count: s.count,
        periodLabel: _periodLabel,
        startDate: _startDate,
        endDate: _endDate,
        color: _tab == 0 ? AppColors.expense : AppColors.income,
      ),
    );
  }

  Widget _empty() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: EmptyState(
          emoji: '📊',
          title: '本期暂无数据',
          hint: '记几笔账后，这里会给你分类占比和环比变化',
          top: 0,
        ),
      );
}

// ── Data model ────────────────────────────────────────────────
class _CatStat {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final String type;
  final double total;
  final int count;

  _CatStat({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    required this.type,
    required this.total,
    required this.count,
  });

  factory _CatStat.fromJson(Map<String, dynamic> j) => _CatStat(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        icon: j['icon'] as String?,
        color: j['color'] as String?,
        type: j['type'] as String? ?? 'expense',
        total: (j['total'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class _AssetPoint {
  final String date; // YYYY-MM-DD
  final double balance;
  _AssetPoint({required this.date, required this.balance});

  factory _AssetPoint.fromJson(Map<String, dynamic> j) => _AssetPoint(
        date: j['date'] as String? ?? '',
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
      );
}

class _MemberStat {
  final String userId;
  final String username;
  final String? nickname;
  final double income;
  final double expense;
  final int count;
  _MemberStat({
    required this.userId,
    required this.username,
    this.nickname,
    required this.income,
    required this.expense,
    required this.count,
  });

  factory _MemberStat.fromJson(Map<String, dynamic> j) => _MemberStat(
        userId: j['userId'] as String? ?? '',
        username: j['username'] as String? ?? '',
        nickname: j['nickname'] as String?,
        income: (j['income'] as num?)?.toDouble() ?? 0,
        expense: (j['expense'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );

  /// 显示名（昵称优先，回退用户名）
  String get displayName {
    final n = (nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return username;
  }
}

// ── 分类明细弹窗：某分类在当前周期里的具体账单 ────────────────
class _CategoryBillsSheet extends StatefulWidget {
  final String categoryId;
  final String type;
  final String name;
  final String icon;
  final double total;
  final int count;
  final String periodLabel;
  final String startDate;
  final String endDate;
  final Color color;
  const _CategoryBillsSheet({
    required this.categoryId,
    required this.type,
    required this.name,
    required this.icon,
    required this.total,
    required this.count,
    required this.periodLabel,
    required this.startDate,
    required this.endDate,
    required this.color,
  });

  @override
  State<_CategoryBillsSheet> createState() => _CategoryBillsSheetState();
}

class _CategoryBillsSheetState extends State<_CategoryBillsSheet> {
  bool _loading = true;
  List<Bill> _bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.getBills(
        categoryId: widget.categoryId,
        type: widget.type,
        startDate: widget.startDate,
        endDate: widget.endDate,
        limit: 200,
      );
      final list = (res['bills'] as List? ?? [])
          .map((b) => Bill.fromJson(b as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _bills = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(children: [
              Text(widget.icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1)),
                    const SizedBox(height: 2),
                    Text('${widget.periodLabel} · ${widget.count}笔',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.text3)),
                  ],
                ),
              ),
              Text(fmtMoney(widget.total),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: widget.color)),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _bills.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('没有明细',
                              style: TextStyle(color: AppColors.text2)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                        itemCount: _bills.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) => _billRow(_bills[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBill(Bill b) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddBillScreen(bill: b)),
    );
    if (changed == true) {
      bumpRefresh(); // 让底层统计页一起刷新
      if (mounted) _load(); // 重新拉本分类明细
    }
  }

  /// 与账单页一致的记录样式：图标头像 + 备注/账户 + 金额/日期
  Widget _billRow(Bill b) {
    final note = b.note.trim();
    final accName = b.account.nameOf(b.ledgerId);
    return InkWell(
      onTap: () => _editBill(b),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color:
                  b.isIncome ? AppColors.incomeLight : AppColors.expenseLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                b.category.icon ?? (b.isIncome ? '💰' : '💸'),
                style: const TextStyle(fontSize: 19),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isEmpty ? widget.name : note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text1),
                ),
                const SizedBox(height: 2),
                Text(accName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(b.amountText,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: widget.color)),
              const SizedBox(height: 2),
              Text(DateFormat('M月d日 HH:mm').format(b.date),
                  style: TextStyle(fontSize: 11, color: AppColors.text2)),
            ],
          ),
        ]),
      ),
    );
  }
}
