import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import 'add_bill_screen.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _scroll = ScrollController();
  List<Bill> _bills = [];
  double _totalIncome  = 0;
  double _totalExpense = 0;
  bool   _loading = true;
  bool   _loadingMore = false;
  bool   _hasMore = true;
  String? _filterType;
  String? _filterUserId;
  _DateMode _dateMode = _DateMode.all;
  DateTime _dateAnchor = DateTime.now();
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  int    _page = 1;

  static final _moneyFmt = NumberFormat('#,##0.00');
  static final _moneyFmtInt = NumberFormat('#,##0');

  String? get _startDate {
    if (_dateMode == _DateMode.all) return null;
    if (_dateMode == _DateMode.range) {
      if (_rangeStart == null) return null;
      return DateFormat('yyyy-MM-dd').format(_rangeStart!);
    }
    if (_dateMode == _DateMode.year) return '${_dateAnchor.year}-01-01';
    final m = _dateAnchor.month.toString().padLeft(2, '0');
    return '${_dateAnchor.year}-$m-01';
  }

  String? get _endDate {
    if (_dateMode == _DateMode.all) return null;
    if (_dateMode == _DateMode.range) {
      if (_rangeEnd == null) return null;
      return DateFormat('yyyy-MM-dd').format(_rangeEnd!);
    }
    if (_dateMode == _DateMode.year) return '${_dateAnchor.year}-12-31';
    final last = DateTime(_dateAnchor.year, _dateAnchor.month + 1, 0).day;
    final m = _dateAnchor.month.toString().padLeft(2, '0');
    return '${_dateAnchor.year}-$m-${last.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    switch (_dateMode) {
      case _DateMode.all:
        return '全部时间';
      case _DateMode.range:
        if (_rangeStart != null && _rangeEnd != null) {
          return '${DateFormat('M/d').format(_rangeStart!)} ~ ${DateFormat('M/d').format(_rangeEnd!)}';
        }
        return '选择范围';
      case _DateMode.year:
        return '${_dateAnchor.year}年';
      case _DateMode.month:
        return '${_dateAnchor.year}年${_dateAnchor.month}月';
    }
  }

  List<({String id, String name})> _members = [];
  bool _isSharedLedger = false;

  @override
  void initState() {
    super.initState();
    refreshBus.addListener(_onBump);
    _loadMembers();
    _load(refresh: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
          !_loadingMore && _hasMore) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMembers() async {
    try {
      final res = await ApiService.getLedgers();
      final ledgers = (res['ledgers'] as List? ?? []);
      final currentId = res['currentLedgerId'] as String?;
      final current = ledgers.cast<Map<String, dynamic>>().firstWhere(
            (l) => l['id'] == currentId,
            orElse: () => {},
          );
      final memberCount = (current['memberCount'] as num?)?.toInt() ?? 1;
      if (memberCount <= 1 || currentId == null) {
        if (mounted) setState(() => _isSharedLedger = false);
        return;
      }
      final mRes = await ApiService.getMembers(currentId);
      final m = (mRes['members'] as List? ?? [])
          .map((e) {
            final em = e as Map;
            final nick = (em['nickname'] as String? ?? '').trim();
            final uname = em['username'] as String? ?? '';
            return (
              id: em['userId'] as String,
              name: nick.isNotEmpty ? nick : uname,
            );
          })
          .toList();
      if (mounted) {
        setState(() {
          _members = m;
          _isSharedLedger = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onBump);
    _scroll.dispose();
    super.dispose();
  }

  void _onBump() {
    if (mounted) _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() { _loading = true; _page = 1; _hasMore = true; });
    }
    try {
      final cur = await AuthService.getCurrentLedgerId();
      if (cur != null && !KeyChain.instance.hasDek(cur)) {
        await PendingDekResolver.rehydrate(requireLedgerId: cur);
      }
      final res = await ApiService.getBills(
        page: 1,
        limit: 20,
        type: _filterType,
        userId: _filterUserId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      setState(() {
        _bills       = (res['bills'] as List? ?? []).map((b) => Bill.fromJson(b)).toList();
        _totalIncome  = (res['summary']?['totalIncome']  as num?)?.toDouble() ?? 0;
        _totalExpense = (res['summary']?['totalExpense'] as num?)?.toDouble() ?? 0;
        _hasMore     = _bills.length >= 20;
        _page        = 2;
        _loading     = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final res = await ApiService.getBills(
        page: _page,
        limit: 20,
        type: _filterType,
        userId: _filterUserId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      final more = (res['bills'] as List? ?? []).map((b) => Bill.fromJson(b)).toList();
      setState(() {
        _bills.addAll(more);
        _hasMore = more.length >= 20;
        _page++;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text('删除「${bill.category.name}」${bill.amountText}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.deleteBill(bill.id);
    bumpRefresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '账单',
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSharedLedger ? 92 : 92),
          child: _filterBar(),
        ),
      ),
      body: AuraBackground(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => _load(refresh: true),
                child: _bills.isEmpty ? _empty() : _list(),
              ),
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Row(children: [
              _dateFilterButton(),
              const Spacer(),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12),
                  children: [
                    if (_totalIncome > 0)
                      TextSpan(
                          text: '+¥${_moneyFmtInt.format(_totalIncome)}  ',
                          style: const TextStyle(
                              color: AppColors.income,
                              fontWeight: FontWeight.w600)),
                    if (_totalExpense > 0)
                      TextSpan(
                          text: '-¥${_moneyFmtInt.format(_totalExpense)}',
                          style: const TextStyle(
                              color: AppColors.expense,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: Row(children: [
              _chip('全部', null),
              const SizedBox(width: 8),
              _chip('收入', 'income'),
              const SizedBox(width: 8),
              _chip('支出', 'expense'),
              if (_isSharedLedger) ...[
                const Spacer(),
                _userFilterButton(),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _dateFilterButton() {
    final isAll = _dateMode == _DateMode.all;
    return InkWell(
      onTap: _openDateSheet,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isAll ? AppColors.surface : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isAll ? AppColors.border : AppColors.primary),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_rounded,
              size: 13,
              color: isAll ? AppColors.text2 : AppColors.primary),
          const SizedBox(width: 6),
          Text(_dateLabel,
              style: TextStyle(
                fontSize: 13,
                color: isAll ? AppColors.text2 : AppColors.primary,
                fontWeight:
                    isAll ? FontWeight.normal : FontWeight.w600,
              )),
          if (_dateMode == _DateMode.range) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  _dateMode = _DateMode.all;
                  _rangeStart = null;
                  _rangeEnd = null;
                });
                _load(refresh: true);
              },
              child: Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
            ),
          ] else if (!isAll) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_dateMode == _DateMode.month) {
                    _dateAnchor = DateTime(
                        _dateAnchor.year, _dateAnchor.month - 1);
                  } else {
                    _dateAnchor = DateTime(_dateAnchor.year - 1, 1);
                  }
                });
                _load(refresh: true);
              },
              child: Icon(Icons.chevron_left_rounded,
                  size: 18, color: AppColors.primary),
            ),
            GestureDetector(
              onTap: _canGoNextDate
                  ? () {
                      setState(() {
                        if (_dateMode == _DateMode.month) {
                          _dateAnchor = DateTime(
                              _dateAnchor.year, _dateAnchor.month + 1);
                        } else {
                          _dateAnchor =
                              DateTime(_dateAnchor.year + 1, 1);
                        }
                      });
                      _load(refresh: true);
                    }
                  : null,
              child: Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: _canGoNextDate
                      ? AppColors.primary
                      : AppColors.text3),
            ),
          ] else
            Icon(Icons.arrow_drop_down_rounded,
                size: 16, color: AppColors.text2),
        ]),
      ),
    );
  }

  bool get _canGoNextDate {
    final now = DateTime.now();
    if (_dateMode == _DateMode.year) return _dateAnchor.year < now.year;
    if (_dateMode == _DateMode.month) {
      return _dateAnchor.isBefore(DateTime(now.year, now.month));
    }
    return false;
  }

  void _openDateSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final now = DateTime.now();
        Widget tile(String label, _DateMode mode, DateTime anchor) {
          final selected = _dateMode == mode &&
              _dateAnchor.year == anchor.year &&
              (mode != _DateMode.month ||
                  _dateAnchor.month == anchor.month);
          return ListTile(
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _dateMode = mode;
                _dateAnchor = anchor;
                _rangeStart = null;
                _rangeEnd = null;
              });
              _load(refresh: true);
            },
            title: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? AppColors.primary
                        : AppColors.text1)),
            trailing: selected
                ? Icon(Icons.check_rounded,
                    color: AppColors.primary, size: 18)
                : null,
            visualDensity:
                const VisualDensity(vertical: -2),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(children: [
                  Text('选择时间',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.text2),
                  ),
                ]),
              ),
              tile('全部时间', _DateMode.all, _dateAnchor),
              Divider(height: 1, color: AppColors.border),
              tile('本月', _DateMode.month,
                  DateTime(now.year, now.month)),
              tile('上月', _DateMode.month,
                  DateTime(now.year, now.month - 1)),
              tile('本年', _DateMode.year, DateTime(now.year)),
              tile('上年', _DateMode.year, DateTime(now.year - 1)),
              Divider(height: 1, color: AppColors.border),
              ListTile(
                title: Text('选择月份…',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.text1)),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: AppColors.text2),
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dateAnchor,
                    firstDate: DateTime(2010),
                    lastDate: DateTime.now(),
                    helpText: '选择月份',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _dateMode = _DateMode.month;
                      _dateAnchor =
                          DateTime(picked.year, picked.month);
                      _rangeStart = null;
                      _rangeEnd = null;
                    });
                    _load(refresh: true);
                  }
                },
              ),
              ListTile(
                title: Text('自定义范围…',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.text1)),
                trailing: Icon(Icons.date_range_rounded,
                    color: AppColors.text2, size: 20),
                onTap: () async {
                  Navigator.pop(context);
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2010),
                    lastDate: now,
                    initialDateRange: _rangeStart != null && _rangeEnd != null
                        ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
                        : DateTimeRange(
                            start: now.subtract(const Duration(days: 30)),
                            end: now),
                    helpText: '选择日期范围',
                    confirmText: '确定',
                    cancelText: '取消',
                    fieldStartHintText: '开始日期',
                    fieldEndHintText: '结束日期',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _dateMode = _DateMode.range;
                      _rangeStart = picked.start;
                      _rangeEnd = picked.end;
                    });
                    _load(refresh: true);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _userFilterButton() {
    final selected = _filterUserId != null;
    final currentName = selected
        ? _members.firstWhere(
            (m) => m.id == _filterUserId,
            orElse: () => (id: '', name: '?'),
          ).name
        : null;
    final label = currentName ?? '全员';
    const allSentinel = '__all__';
    return PopupMenuButton<String>(
      tooltip: '按记账人筛选',
      onSelected: (v) {
        final next = v == allSentinel ? null : v;
        if (_filterUserId == next) return;
        setState(() => _filterUserId = next);
        _load(refresh: true);
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: allSentinel,
          child: Row(children: [
            Icon(Icons.groups_rounded,
                size: 18,
                color: _filterUserId == null
                    ? AppColors.primary
                    : AppColors.text2),
            const SizedBox(width: 10),
            Text('全员',
                style: TextStyle(
                    color: _filterUserId == null
                        ? AppColors.primary
                        : AppColors.text1,
                    fontWeight: _filterUserId == null
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ]),
        ),
        ..._members.map((m) => PopupMenuItem<String>(
              value: m.id,
              child: Row(children: [
                CircleAvatar(
                  radius: 9,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    m.name.isEmpty
                        ? '?'
                        : m.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Text(m.name,
                    style: TextStyle(
                        color: _filterUserId == m.id
                            ? AppColors.primary
                            : AppColors.text1,
                        fontWeight: _filterUserId == m.id
                            ? FontWeight.w600
                            : FontWeight.normal)),
              ]),
            )),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_outline_rounded,
              size: 14,
              color: selected ? AppColors.primary : AppColors.text2),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? AppColors.primary : AppColors.text2,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              )),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down_rounded,
              size: 16,
              color: selected ? AppColors.primary : AppColors.text2),
        ]),
      ),
    );
  }

  Widget _chip(String label, String? type) {
    final selected = _filterType == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (_filterType == type) return;
        setState(() => _filterType = type);
        _load(refresh: true);
      },
      selectedColor: AppColors.primaryLight,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.text2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
    );
  }

  Widget _list() {
    final dayGroups = <String, List<Bill>>{};
    for (final b in _bills) {
      final dayKey = DateFormat('yyyy-MM-dd').format(b.date);
      dayGroups.putIfAbsent(dayKey, () => []).add(b);
    }
    final dayKeys = dayGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: dayKeys.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == dayKeys.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final dayKey = dayKeys[i];
        final items = dayGroups[dayKey]!;
        final dayIncome = items
            .where((b) => b.isIncome)
            .fold(0.0, (s, b) => s + b.amount);
        final dayExpense = items
            .where((b) => !b.isIncome)
            .fold(0.0, (s, b) => s + b.amount);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(children: [
                  Text(_formatDate(dayKey),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2)),
                  const Spacer(),
                  if (dayIncome > 0)
                    Text('+¥${_moneyFmt.format(dayIncome)} ',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.income)),
                  if (dayExpense > 0)
                    Text('-¥${_moneyFmt.format(dayExpense)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.expense)),
                ]),
              ),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: items.map((bill) {
                    final isLast = items.last == bill;
                    return _BillTile(
                      bill: bill,
                      showDivider: !isLast,
                      showRecorder: _isSharedLedger,
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AddBillScreen(bill: bill),
                          ),
                        );
                        if (result == true) _load(refresh: true);
                      },
                      onDelete: () => _deleteBill(bill),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now  = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today)     return '今天';
    if (d == yesterday) return '昨天';
    if (date.year == now.year) {
      return DateFormat('M月d日 EEEE', 'zh').format(date);
    }
    return DateFormat('yyyy年M月d日 EEEE', 'zh').format(date);
  }

  Widget _empty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🧾', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('还没有账单', style: TextStyle(color: AppColors.text2, fontSize: 16)),
          const SizedBox(height: 6),
          Text('点击右下角 + 开始记账',
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
        ]),
      );
}

class _BillTile extends StatelessWidget {
  const _BillTile({
    required this.bill,
    required this.showDivider,
    required this.onTap,
    required this.onDelete,
    this.showRecorder = false,
  });
  final Bill bill;
  final bool showDivider;
  final bool showRecorder;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: bill.isIncome ? AppColors.incomeLight : AppColors.expenseLight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    bill.category.icon ?? (bill.isIncome ? '💰' : '💸'),
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(bill.category.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text1)),
                    ),
                    if (showRecorder && bill.recorderName != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(bill.recorderName!,
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.text2,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Builder(builder: (_) {
                    final accName = bill.account.nameOf(bill.ledgerId);
                    return Text(
                      bill.note.isEmpty
                          ? accName
                          : '$accName  ${bill.note}',
                      style: TextStyle(fontSize: 12, color: AppColors.text2),
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(bill.amountText,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: bill.isIncome ? AppColors.income : AppColors.expense)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm').format(bill.date),
                    style: TextStyle(fontSize: 11, color: AppColors.text2)),
              ]),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.text2),
                ),
              ),
            ]),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 66),
      ],
    );
  }
}

enum _DateMode { all, month, year, range }
