import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import 'add_bill_screen.dart';

class BillsScreen extends StatefulWidget {
  /// true=作为底部 tab（左上头像、透明底）；false=二级页（返回箭头、bg 底）
  const BillsScreen({
    super.key,
    this.isTab = false,
    this.initialType,
    this.initialUserIds,
    this.initialRangeStart,
    this.initialRangeEnd,
  });
  final bool isTab;
  /// 从统计页等跳入时的预选过滤（对账用）：类型 / 记账人 / 日期范围
  final String? initialType; // 'income' / 'expense'
  final List<String>? initialUserIds;
  final DateTime? initialRangeStart;
  final DateTime? initialRangeEnd;
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
  bool _filterTransfersOnly = false; // 类型筛选=只看转账（转账不算收支）
  String? _filterSource; // 来源筛选（'stock'=只看股票盈亏）
  final Set<String> _filterUserIds = {}; // 成员多选
  final Set<String> _filterAccountIds = {}; // 账户多选
  final Set<String> _filterCategoryIds = {}; // 分类多选
  final Map<String, String> _catLabelById = {}; // id -> 「icon 名称」
  List<Category> _allCategories = []; // 懒加载缓存（分类筛选用）
  double? _minAmount; // 金额范围筛选（含边界）
  double? _maxAmount;
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
  List<Account> _accounts = [];
  bool _isSharedLedger = false;

  @override
  void initState() {
    super.initState();
    // 统计页跳入：预选过滤条件
    _filterType = widget.initialType;
    if (widget.initialUserIds != null) {
      _filterUserIds.addAll(widget.initialUserIds!);
    }
    if (widget.initialRangeStart != null || widget.initialRangeEnd != null) {
      _dateMode = _DateMode.range;
      _rangeStart = widget.initialRangeStart;
      _rangeEnd = widget.initialRangeEnd;
    }
    refreshBus.addListener(_onBump);
    _loadMembers();
    _loadAccounts();
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

  Future<void> _loadAccounts() async {
    try {
      // scope:'all' = 账本下全部账户（含其他成员私人账户，按人分组展示）
      final res = await ApiService.getAccounts(scope: 'all');
      final list = (res['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _accounts = list);
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
        isTransfer: _filterTransfersOnly
            ? 'true'
            : (_filterSource != null ? 'false' : null),
        source: _filterSource,
        userIds: _filterUserIds.toList(),
        accountIds: _filterAccountIds.toList(),
        categoryIds: _filterCategoryIds.toList(),
        startDate: _startDate,
        endDate: _endDate,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
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
        isTransfer: _filterTransfersOnly
            ? 'true'
            : (_filterSource != null ? 'false' : null),
        source: _filterSource,
        userIds: _filterUserIds.toList(),
        accountIds: _filterAccountIds.toList(),
        categoryIds: _filterCategoryIds.toList(),
        startDate: _startDate,
        endDate: _endDate,
        minAmount: _minAmount,
        maxAmount: _maxAmount,
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
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
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
      backgroundColor: widget.isTab ? Colors.transparent : AppColors.bg,
      appBar: AuraAppBar(
        title: '账单',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _filterEntryButton(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: _filterBar(),
        ),
      ),
      // tab 模式下 main_screen 已铺全局 AuraBackground，别再包一层（背景会错位）
      body: _wrapBg(
        _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => _load(refresh: true),
                child: _bills.isEmpty ? _empty() : _list(),
              ),
      ),
    );
  }

  Widget _wrapBg(Widget child) =>
      widget.isTab ? child : AuraBackground(child: child);

  Widget _filterBar() {
    final balance = _totalIncome - _totalExpense;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(children: [
            Text('收 +¥${_moneyFmtInt.format(_totalIncome)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.income,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
            Text('支 -¥${_moneyFmtInt.format(_totalExpense)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.expense,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
            Text('结余 ¥${_moneyFmtInt.format(balance)}',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Future<void> _showCategoryFilterSheet() async {
    // 懒加载分类（含系统 + 自建），只拉一次
    if (_allCategories.isEmpty) {
      try {
        final res = await ApiService.getCategories();
        _allCategories = (res['categories'] as List? ?? [])
            .map((e) => Category.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    final roots = _allCategories.where((c) => c.isRoot).toList();
    final expenseRoots = roots.where((c) => c.type == 'expense').toList();
    final incomeRoots = roots.where((c) => c.type == 'income').toList();

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text3)),
        );

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) {
          Widget row(Category c) {
            final on = _filterCategoryIds.contains(c.id);
            return InkWell(
              onTap: () {
                // 多选：再点已选的一项即取消；弹层不关，可继续选
                setState(() {
                  if (on) {
                    _filterCategoryIds.remove(c.id);
                  } else {
                    _filterCategoryIds.add(c.id);
                    _catLabelById[c.id] = '${c.displayIcon} ${c.name}';
                  }
                });
                setSheet(() {});
                _load(refresh: true);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(children: [
                  Text(c.displayIcon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                on ? FontWeight.w600 : FontWeight.w500,
                            color: on ? AppColors.primary : AppColors.text1)),
                  ),
                  if (on)
                    Icon(Icons.check_rounded,
                        size: 18, color: AppColors.primary),
                ]),
              ),
            );
          }

          return ListView(
            controller: controller,
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 与「类型」筛选联动：选了收入就只列收入分类，反之亦然
              if (_filterType != 'income') ...[
                sectionTitle('支出分类（含其下二级）'),
                ...expenseRoots.map(row),
              ],
              if (_filterType != 'expense') ...[
                sectionTitle('收入分类'),
                ...incomeRoots.map(row),
              ],
            ],
          );
        },
        ),
      ),
    );
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
                // 点已选的时间段 = 取消（回到全部时间）
                if (selected && mode != _DateMode.all) {
                  _dateMode = _DateMode.all;
                } else {
                  _dateMode = mode;
                  _dateAnchor = anchor;
                }
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

  /// 账户筛选弹窗：账本下全部账户，按 共享 / 各成员 分组
  Future<void> _showAccountFilterSheet() async {
    // 账户跟着「记账人」筛选走：选了成员就只列他们的账户 + 共享账户
    final scoped = _filterUserIds.isEmpty
        ? _accounts
        : _accounts
            .where((a) =>
                a.isShared || _filterUserIds.contains(a.ownerId))
            .toList();
    final shared = scoped.where((a) => a.isShared).toList();
    final byOwner = <String, List<Account>>{};
    final ownerName = <String, String>{};
    for (final a in scoped) {
      if (a.isShared) continue;
      final oid = a.ownerId ?? '';
      byOwner.putIfAbsent(oid, () => []).add(a);
      final dn = (a.ownerDisplayName ?? '').trim();
      ownerName[oid] = dn.isEmpty ? '其他成员' : dn;
    }
    // "我的"（balanceVisible）排最前，其余按名字
    final ownerIds = byOwner.keys.toList()
      ..sort((x, y) {
        final mx = byOwner[x]!.first.balanceVisible;
        final my = byOwner[y]!.first.balanceVisible;
        if (mx != my) return mx ? -1 : 1;
        return ownerName[x]!.compareTo(ownerName[y]!);
      });

    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
        );
    Widget item(BuildContext ctx,
        {required bool sel,
        required String emoji,
        required String name,
        required VoidCallback onTap}) {
      return ListTile(
        dense: true,
        onTap: onTap,
        leading: Text(emoji, style: const TextStyle(fontSize: 20)),
        title: Text(name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14,
                color: sel ? AppColors.primary : AppColors.text1,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        trailing: sel
            ? Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.primary)
            : null,
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(children: [
                  Text('按账户筛选',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: AppColors.text2),
                  ),
                ]),
              ),
              Divider(height: 1, color: AppColors.border),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    item(ctx,
                        sel: _filterAccountIds.isEmpty,
                        emoji: '📋',
                        name: '全部账户',
                        onTap: () {
                          setState(() => _filterAccountIds.clear());
                          setSheet(() {});
                          _load(refresh: true);
                        }),
                    if (shared.isNotEmpty) head('共享账户'),
                    ...shared.map((a) => item(ctx,
                        sel: _filterAccountIds.contains(a.id),
                        emoji: a.typeEmoji,
                        name: a.name,
                        onTap: () => _toggleAccount(a.id, setSheet))),
                    for (final oid in ownerIds) ...[
                      head(byOwner[oid]!.first.balanceVisible
                          ? '我的账户'
                          : '${ownerName[oid]} 的账户'),
                      ...byOwner[oid]!.map((a) => item(ctx,
                          sel: _filterAccountIds.contains(a.id),
                          emoji: a.typeEmoji,
                          name: a.name,
                          onTap: () => _toggleAccount(a.id, setSheet))),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// 账户多选 toggle：点已选=取消；弹层保持打开
  void _toggleAccount(String id, void Function(void Function()) setSheet) {
    setState(() {
      if (_filterAccountIds.contains(id)) {
        _filterAccountIds.remove(id);
      } else {
        _filterAccountIds.add(id);
      }
    });
    setSheet(() {});
    _load(refresh: true);
  }

  // ── 筛选抽屉 ────────────────────────────────────────────────

  bool get _anyFilterActive =>
      _filterUserIds.isNotEmpty ||
      _filterAccountIds.isNotEmpty ||
      _filterCategoryIds.isNotEmpty ||
      _filterType != null ||
      _filterTransfersOnly ||
      _filterSource != null ||
      _dateMode != _DateMode.all ||
      _minAmount != null ||
      _maxAmount != null;

  /// header 上的筛选入口：有生效筛选时右上角亮一个主色小圆点
  Widget _filterEntryButton() => GestureDetector(
        onTap: () async {
          // 分类数据懒加载一次，进抽屉前备好
          if (_allCategories.isEmpty) {
            try {
              final res = await ApiService.getCategories();
              _allCategories = (res['categories'] as List? ?? [])
                  .map((e) => Category.fromJson(e as Map<String, dynamic>))
                  .toList();
            } catch (_) {}
          }
          _openFilterPanel();
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.tune_rounded, size: 22, color: AppColors.text1),
            if (_anyFilterActive)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      );

  String get _memberLabel {
    if (_filterUserIds.isEmpty) return '全员';
    if (_filterUserIds.length == 1) {
      return _members
          .firstWhere((m) => m.id == _filterUserIds.first,
              orElse: () => (id: '', name: '成员'))
          .name;
    }
    return '${_filterUserIds.length} 人';
  }

  String get _accountLabel {
    if (_filterAccountIds.isEmpty) return '全部账户';
    if (_filterAccountIds.length == 1) {
      for (final a in _accounts) {
        if (a.id == _filterAccountIds.first) return a.name;
      }
      return '1 个账户';
    }
    return '${_filterAccountIds.length} 个账户';
  }

  /// 分类筛选的展示：0=全部、1=具体名、多=N 个分类
  String get _categoryFilterLabel {
    if (_filterCategoryIds.isEmpty) return '全部分类';
    if (_filterCategoryIds.length == 1) {
      return _catLabelById[_filterCategoryIds.first] ?? '1 个分类';
    }
    return '${_filterCategoryIds.length} 个分类';
  }

  String get _typeLabel => _filterTransfersOnly
      ? '转账'
      : _filterSource == 'stock'
          ? '股票盈亏'
          : _filterType == 'income'
              ? '收入'
              : _filterType == 'expense'
                  ? '支出'
                  : '全部';

  String get _amountLabel {
    if (_minAmount == null && _maxAmount == null) return '不限';
    final min = _minAmount == null ? '' : '¥${_moneyFmtInt.format(_minAmount)}';
    final max = _maxAmount == null ? '' : '¥${_moneyFmtInt.format(_maxAmount)}';
    if (min.isEmpty) return '≤ $max';
    if (max.isEmpty) return '≥ $min';
    return '$min ~ $max';
  }

  /// 筛选面板：root navigator 上的右滑覆盖层——盖住底部导航（Drawer 做不到）
  Future<void> _openFilterPanel() {
    return showGeneralDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '筛选',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      pageBuilder: (dialogCtx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            // 每次点开子选择器后 setLocal 刷新面板上的当前值
            Future<void> pick(Future<void> Function() fn) async {
              await fn();
              setLocal(() {});
            }

            return Material(
              color: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(20)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 300,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
                        child: Row(children: [
                          Text('筛选',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text1)),
                          const Spacer(),
                          TextButton(
                            onPressed: _anyFilterActive
                                ? () {
                                    setState(() {
                                      _filterUserIds.clear();
                                      _filterAccountIds.clear();
                                      _filterCategoryIds.clear();
                                      _filterType = null;
                                      _filterTransfersOnly = false;
                                      _filterSource = null;
                                      _dateMode = _DateMode.all;
                                      _rangeStart = null;
                                      _rangeEnd = null;
                                      _minAmount = null;
                                      _maxAmount = null;
                                    });
                                    setLocal(() {});
                                    _load(refresh: true);
                                  }
                                : null,
                            child: const Text('重置'),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            if (_isSharedLedger)
                              _drawerRow(
                                icon: Icons.person_outline_rounded,
                                label: '成员',
                                value: _memberLabel,
                                active: _filterUserIds.isNotEmpty,
                                onTap: () => pick(_pickMember),
                              ),
                            if (_accounts.isNotEmpty)
                              _drawerRow(
                                icon: Icons.account_balance_wallet_outlined,
                                label: '账户',
                                value: _accountLabel,
                                active: _filterAccountIds.isNotEmpty,
                                onTap: () => pick(_showAccountFilterSheet),
                              ),
                            _drawerRow(
                              icon: Icons.sell_outlined,
                              label: '分类',
                              value: _categoryFilterLabel,
                              active: _filterCategoryIds.isNotEmpty,
                              onTap: () => pick(_showCategoryFilterSheet),
                            ),
                            _drawerRow(
                              icon: Icons.calendar_today_rounded,
                              label: '时间',
                              value: _dateLabel,
                              active: _dateMode != _DateMode.all,
                              onTap: () => pick(() async => _openDateSheet()),
                            ),
                            _drawerRow(
                              icon: Icons.swap_vert_rounded,
                              label: '类型',
                              value: _typeLabel,
                              active: _filterType != null ||
                                  _filterTransfersOnly ||
                                  _filterSource != null,
                              onTap: () => pick(_pickType),
                            ),
                            _drawerRow(
                              icon: Icons.payments_outlined,
                              label: '金额范围',
                              value: _amountLabel,
                              active: _minAmount != null || _maxAmount != null,
                              onTap: () => pick(_pickAmountRange),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('完成'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _drawerRow({
    required IconData icon,
    required String label,
    required String value,
    required bool active,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(children: [
            Icon(icon,
                size: 18, color: active ? AppColors.primary : AppColors.text3),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(fontSize: 14, color: AppColors.text1)),
            const SizedBox(width: 12),
            // 值列右对齐（Expanded+end），所有行的值和箭头贴齐右缘
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? AppColors.primary : AppColors.text3)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 17, color: AppColors.text3),
          ]),
        ),
      );

  /// 成员选择（抽屉行入口）：多选，点已选取消；「全员」清空
  Future<void> _pickMember() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 14),
            ListTile(
              dense: true,
              leading: Icon(Icons.groups_rounded,
                  size: 20,
                  color: _filterUserIds.isEmpty
                      ? AppColors.primary
                      : AppColors.text2),
              title: Text('全员',
                  style: TextStyle(
                      color: _filterUserIds.isEmpty
                          ? AppColors.primary
                          : AppColors.text1,
                      fontWeight: _filterUserIds.isEmpty
                          ? FontWeight.w600
                          : FontWeight.normal)),
              onTap: () {
                setState(() {
                  _filterUserIds.clear();
                });
                setSheet(() {});
                _load(refresh: true);
              },
            ),
            for (final m in _members)
              Builder(builder: (_) {
                final on = _filterUserIds.contains(m.id);
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.person_outline_rounded,
                      size: 20,
                      color: on ? AppColors.primary : AppColors.text2),
                  title: Text(m.name,
                      style: TextStyle(
                          color: on ? AppColors.primary : AppColors.text1,
                          fontWeight:
                              on ? FontWeight.w600 : FontWeight.normal)),
                  trailing: on
                      ? Icon(Icons.check_rounded,
                          size: 18, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      if (on) {
                        _filterUserIds.remove(m.id);
                      } else {
                        _filterUserIds.add(m.id);
                      }
                      // 账户跟着成员走：清掉不属于所选成员的非共享账户
                      if (_filterUserIds.isNotEmpty) {
                        final byId = {for (final a in _accounts) a.id: a};
                        _filterAccountIds.removeWhere((id) {
                          final a = byId[id];
                          if (a == null) return true;
                          if (a.isShared) return false;
                          return !_filterUserIds.contains(a.ownerId);
                        });
                      }
                    });
                    setSheet(() {});
                    _load(refresh: true);
                  },
                );
              }),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  /// 类型选择（抽屉行入口）
  Future<void> _pickType() async {
    const kTransfer = '__transfer__';
    const kStock = '__stock__';
    bool selOf(String? v) {
      if (v == kTransfer) return _filterTransfersOnly;
      if (v == kStock) return _filterSource == 'stock';
      return !_filterTransfersOnly && _filterSource == null && _filterType == v;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          for (final e in const [
            (null, '全部'),
            ('income', '收入'),
            ('expense', '支出'),
            (kTransfer, '转账'),
            (kStock, '股票盈亏'),
          ])
            ListTile(
              dense: true,
              title: Text(e.$2,
                  style: TextStyle(
                      color: selOf(e.$1) ? AppColors.primary : AppColors.text1,
                      fontWeight: selOf(e.$1)
                          ? FontWeight.w600
                          : FontWeight.normal)),
              onTap: () {
                Navigator.pop(ctx);
                // 点已选的类型 = 取消（回到全部）
                setState(() {
                  if (e.$1 == kTransfer) {
                    _filterTransfersOnly = !_filterTransfersOnly;
                    if (_filterTransfersOnly) {
                      _filterType = null;
                      _filterSource = null;
                    }
                    return;
                  }
                  if (e.$1 == kStock) {
                    _filterSource = _filterSource == 'stock' ? null : 'stock';
                    if (_filterSource != null) {
                      _filterType = null;
                      _filterTransfersOnly = false;
                    }
                    return;
                  }
                  _filterTransfersOnly = false;
                  _filterSource = null;
                  final next = _filterType == e.$1 ? null : e.$1;
                  if (_filterType == next) return;
                  _filterType = next;
                  // 联动：清掉与新类型冲突的已选分类（收入类型配支出分类无意义）
                  if (next != null && _filterCategoryIds.isNotEmpty) {
                    final byId = {for (final c in _allCategories) c.id: c};
                    _filterCategoryIds.removeWhere(
                        (id) => byId[id] != null && byId[id]!.type != next);
                  }
                });
                _load(refresh: true);
              },
            ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  /// 金额范围（抽屉行入口）：最低/最高两个输入框
  Future<void> _pickAmountRange() async {
    final minCtrl = TextEditingController(
        text: _minAmount == null ? '' : _minAmount!.toStringAsFixed(0));
    final maxCtrl = TextEditingController(
        text: _maxAmount == null ? '' : _maxAmount!.toStringAsFixed(0));
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('金额范围',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text1)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '最低', prefixText: '¥'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('—'),
            ),
            Expanded(
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '最高', prefixText: '¥'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final min = double.tryParse(minCtrl.text.trim());
                final max = double.tryParse(maxCtrl.text.trim());
                Navigator.pop(ctx);
                setState(() {
                  _minAmount = (min != null && min > 0) ? min : null;
                  _maxAmount = (max != null && max > 0) ? max : null;
                });
                _load(refresh: true);
              },
              child: const Text('应用'),
            ),
          ),
        ]),
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
        // 小计口径与汇总一致：转账腿与股票纸面盈亏都不计收支
        final dayIncome = items
            .where((b) => b.isIncome && !b.isTransfer && b.source != 'stock')
            .fold(0.0, (s, b) => s + b.amount);
        final dayExpense = items
            .where((b) => !b.isIncome && !b.isTransfer && b.source != 'stock')
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

  Widget _empty() => const Center(
        child: EmptyState(
          emoji: '🧾',
          title: '还没有账单',
          hint: '去首页点结余卡的「记一笔」开始',
          top: 0,
        ),
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

  /// 记账人只显示首字（中文取第一个字，英文取首字母并大写）
  String _recorderInitial(String name) {
    final s = name.trim();
    if (s.isEmpty) return '';
    return String.fromCharCodes(s.runes.take(1)).toUpperCase();
  }

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
                  // 转账账单一律显示 🔄（分类可能是历史贴错的，不直接展示）
                  child: Text(
                    bill.isTransfer
                        ? '🔄'
                        : (bill.category.icon ?? (bill.isIncome ? '💰' : '💸')),
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(bill.isTransfer ? '转账' : bill.category.name,
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
                        child: Text(_recorderInitial(bill.recorderName!),
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
              // 股票盈亏账单由每日结算维护，只读不删
              if (bill.source == 'stock')
                const SizedBox(width: 26)
              else
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
