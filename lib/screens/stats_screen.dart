import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../models/bill.dart';
import '../widgets/glass.dart';
import 'profile_screen.dart';

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
  List<_AssetPoint> _assetTrend = [];

  // 多人账本：按记账人聚合
  List<_MemberStat> _memberStats = [];

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

  String get _startDate {
    if (_period == _Period.year) return '${_anchor.year}-01-01';
    return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-01';
  }

  String get _endDate {
    if (_period == _Period.year) return '${_anchor.year}-12-31';
    final last = DateTime(_anchor.year, _anchor.month + 1, 0).day;
    return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
  }

  String get _periodLabel {
    if (_period == _Period.year) return '${_anchor.year}年';
    return DateFormat('yyyy年M月').format(_anchor);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getStats(
          startDate: _startDate, endDate: _endDate);
      if (!mounted) return;
      final sum = (res['summary'] as Map?) ?? {};
      final rawStats = (res['categoryStats'] as List? ?? [])
          .map((e) => _CatStat.fromJson(e as Map<String, dynamic>))
          .toList();
      final asset = (res['assetSummary'] as Map?) ?? {};
      final trendRaw = (res['assetTrend'] as List? ?? []);
      setState(() {
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
  // 由主题色派生 8 个层次（HSL 调整明度），保持视觉统一
  List<Color> get _palette {
    final base = HSLColor.fromColor(AppColors.primary);
    final steps = <double>[0.0, -0.10, 0.08, -0.18, 0.16, -0.05, 0.24, -0.25];
    return steps.map((d) {
      final l = (base.lightness + d).clamp(0.18, 0.78);
      return base.withLightness(l).toColor();
    }).toList();
  }

  Color _colorFor(int i) => _palette[i % _palette.length];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AuraAppBar(
        title: '统计',
        avatarTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _periodToggle()),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
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
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _periodChip('月', _Period.month),
        _periodChip('年', _Period.year),
      ]),
    );
  }

  Widget _periodChip(String label, _Period p) {
    final sel = _period == p;
    return GestureDetector(
      onTap: () => _switchPeriod(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel ? AppColors.onPrimary : AppColors.text2)),
      ),
    );
  }

  // ── Date navigator ────────────────────────────────────────────
  Widget _dateNav() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(children: [
          IconButton(
            onPressed: _prev,
            icon: Icon(Icons.chevron_left_rounded,
                color: AppColors.text2),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
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
          const SizedBox(width: 4),
          IconButton(
            onPressed: _canGoNext ? _next : null,
            icon: Icon(Icons.chevron_right_rounded,
                color: _canGoNext ? AppColors.text2 : AppColors.border),
            padding: EdgeInsets.zero,
          ),
        ]),
      );

  // ── Asset card（家庭资产卡 + 走势线图） ────────────────────
  Widget _assetCard() {
    final hasShared = _assetShared.abs() > 0.01;
    final hasOthers = _assetOthers.abs() > 0.01;
    final isFamily = hasShared || hasOthers;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(isFamily ? '家庭总资产' : '总资产',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const Spacer(),
            Text(_periodLabel,
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('¥',
                  style: TextStyle(
                      fontSize: 18,
                      color: AppColors.text1,
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 2),
              Text(
                fmtMoney(_assetTotal),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1,
                    letterSpacing: -0.5),
              ),
            ],
          ),
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

  Widget _assetMiniStat(String label, double value, double dotOpacity) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(dotOpacity),
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
        gridData: const FlGridData(show: false),
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
                    ? p.date.substring(5, 7) + '月'
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
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.text1,
            getTooltipItems: (items) => items.map((it) {
              final idx = it.x.toInt();
              final date = _assetTrend[idx].date;
              return LineTooltipItem(
                '$date\n${fmtMoney(it.y)}',
                TextStyle(
                    color: AppColors.surface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
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
                  AppColors.primary.withOpacity(0.18),
                  AppColors.primary.withOpacity(0.0),
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
            AppColors.incomeLight),
        const SizedBox(width: 10),
        _summaryCard('支出', _totalExpense, AppColors.expense,
            AppColors.expenseLight),
        const SizedBox(width: 10),
        _summaryCard('结余', _totalIncome - _totalExpense,
            AppColors.primary, AppColors.primaryLight),
      ]);

  Widget _summaryCard(
      String label, double amount, Color color, Color bg) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              '${fmtMoneyInt(amount.abs())}',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: -0.5),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      );

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
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────
  Widget _tabBar() => Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          _tabBtn('支出', 0),
          _tabBtn('收入', 1),
        ]),
      );

  Widget _tabBtn(String label, int idx) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _tab = idx;
            _touchedIndex = -1;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _tab == idx ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          _tab == idx ? AppColors.onPrimary : AppColors.text2)),
            ),
          ),
        ),
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
                    color: _colorFor(i),
                    radius: touched ? 54 : 46,
                    title: touched
                        ? '${pct.toStringAsFixed(1)}%'
                        : '',
                    titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
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
                        color: _colorFor(i),
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
                    Text(
                      fmtMoneyInt(s.total),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1),
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
  Widget _categoryList() {
    final stats = _currentStats;
    final total = _currentTotal > 0 ? _currentTotal : 1;
    final color = _tab == 0 ? AppColors.expense : AppColors.income;

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
              Padding(
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
                              Text(fmtMoney(s.total),
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: color)),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Text('${s.count}笔',
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
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _colorFor(i)),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast) const Divider(height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            Text('📊', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('暂无数据',
                style: TextStyle(color: AppColors.text2, fontSize: 16)),
          ],
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
