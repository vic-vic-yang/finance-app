import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/bill_parser.dart';
import '../services/recents_service.dart';
import '../widgets/ocr_input_sheet.dart';
import '../widgets/voice_input_sheet.dart';

class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key, this.bill});
  final Bill? bill;

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  /// 'expense' / 'income' / 'transfer'
  String _type = 'expense';

  /// 已提交的项（带操作符）。例如 [+34, +23, -12]
  /// 操作符是这一项 *相对于前一项* 的运算
  final List<_Term> _terms = [];

  /// 当前正在输入的那一段数字
  String _amountStr = '';

  /// 下一个数字提交时用的操作符（仅 '+' / '-'）
  String _pendingOp = '+';

  DateTime _date = DateTime.now();
  final _noteCtrl = TextEditingController();

  List<Category> _categories = [];
  /// 当前用户可用账户（共享 + 自己的私人），用作"账户/转出"选项
  List<Account> _accounts = [];
  /// 账本下所有账户（含其他成员私人账户，余额不可见），仅用作"转账目的地"选项
  List<Account> _allAccounts = [];
  Category? _selectedCategory;
  Account? _selectedAccount;
  /// 转账目的地账户（可以是其他成员的私人账户）
  Account? _toAccount;
  bool _saving = false;
  bool _loaded = false;

  bool get _isTransfer => _type == 'transfer';

  // 总金额（所有 terms + 当前未提交的 amountStr）
  double get _total {
    double sum = _terms.fold(
        0.0, (s, t) => s + (t.op == '+' ? t.value : -t.value));
    final cur = double.tryParse(_amountStr) ?? 0.0;
    if (_amountStr.isNotEmpty) {
      sum += (_pendingOp == '+' ? cur : -cur);
    }
    return sum;
  }

  /// 何时显示算式行：
  /// - 已经有提交的 term（例如 "100 +"）
  /// - 或者用户按了 - 当作开头负号
  bool get _hasExpression =>
      _terms.isNotEmpty || (_amountStr.isEmpty && _pendingOp != '+');

  /// 展示用的算式串，例如 "34 + 23 - 12"，或挂起态 "100 +"
  String get _displayExpr {
    final buf = StringBuffer();
    String fmt(double v) {
      return v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(2);
    }
    for (int i = 0; i < _terms.length; i++) {
      final t = _terms[i];
      if (i == 0) {
        if (t.op == '-') buf.write('-');
      } else {
        buf.write(' ${t.op} ');
      }
      buf.write(fmt(t.value));
    }
    if (_amountStr.isNotEmpty) {
      if (buf.isEmpty) {
        if (_pendingOp == '-') buf.write('-');
      } else {
        buf.write(' $_pendingOp ');
      }
      buf.write(_amountStr);
    } else if (_terms.isNotEmpty) {
      // 已有 term，挂起一个操作符等待下一个数字 —— 让用户立刻看到点了 + / -
      buf.write(' $_pendingOp');
    } else if (_pendingOp != '+') {
      // 还没输入任何数字就按了 -，提示用户后面会取负
      buf.write(_pendingOp);
    }
    return buf.toString();
  }

  @override
  void initState() {
    super.initState();
    final b = widget.bill;
    _type = b?.type ?? 'expense';
    // 编辑模式不允许切到"转账"（转账目前不支持编辑）
    final tabLen = widget.bill != null ? 2 : 3;
    _tabCtrl = TabController(
        length: tabLen,
        vsync: this,
        initialIndex: _type == 'expense' ? 0 : 1);
    _tabCtrl.addListener(_onTabChanged);

    if (b != null) {
      _amountStr = b.amount.toStringAsFixed(2);
      _date = b.date;
      _noteCtrl.text = b.note;
    }
    _loadData();
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    setState(() {
      switch (_tabCtrl.index) {
        case 0:
          _type = 'expense';
          break;
        case 1:
          _type = 'income';
          break;
        case 2:
          _type = 'transfer';
          break;
      }
      _selectedCategory = _filteredCategories.isNotEmpty
          ? _filteredCategories.first
          : null;
      // 初次切到转账，默认 from = 当前选中账户，to = 选第一个不同的账户
      if (_isTransfer) {
        _ensureTransferDefaults();
      }
    });
  }

  void _ensureTransferDefaults() {
    _selectedAccount ??= _accounts.isNotEmpty ? _accounts.first : null;
    if (_toAccount == null || _toAccount!.id == _selectedAccount?.id) {
      // 从"所有账户"中选第一个跟 from 不同的
      Account? candidate;
      for (final a in _allAccounts) {
        if (a.id != _selectedAccount?.id) {
          candidate = a;
          break;
        }
      }
      _toAccount = candidate;
    }
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getCategories(),
        ApiService.getAccounts(),
        // 拉一次"全部账户"用于转账目的地（含他人私人账户，余额已隐藏）
        ApiService.getAccounts(scope: 'all'),
      ]);
      if (!mounted) return;

      final allCats = (results[0]['categories'] as List? ?? [])
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .toList();
      final myAccounts = (results[1]['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      final everyAccount = (results[2]['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();

      final b = widget.bill;
      Category? initCat;
      Account? initAcc;

      if (b != null) {
        initCat = allCats.firstWhere(
          (c) => c.id == b.category.id,
          orElse: () => allCats.isNotEmpty ? allCats.first : Category(id: '', name: '', type: _type),
        );
        initAcc = myAccounts.firstWhere(
          (a) => a.id == b.account.id,
          orElse: () => myAccounts.isNotEmpty
              ? myAccounts.first
              : Account(
                  id: '',
                  ledgerId: '',
                  nameCipher: null,
                  type: 'CASH',
                  balance: 0,
                ),
        );
      } else {
        final typed = allCats.where((c) => c.type == _type).toList();
        if (typed.isNotEmpty) initCat = typed.first;
        if (myAccounts.isNotEmpty) initAcc = myAccounts.first;
      }

      setState(() {
        _categories = allCats;
        _accounts = myAccounts;
        _allAccounts = everyAccount;
        _selectedCategory = initCat;
        _selectedAccount = initAcc;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  List<Category> get _filteredCategories =>
      _categories.where((c) => c.type == _type).toList();

  // ── Numpad ────────────────────────────────────────────────────
  void _onKey(String k) {
    // "完成"键直接保存（不再走 setState）
    if (k == '✓') {
      _save();
      return;
    }
    setState(() {
      if (k == '⌫') {
        _backspace();
      } else if (k == '+' || k == '-') {
        _onOperator(k);
      } else if (k == '.') {
        if (!_amountStr.contains('.')) {
          _amountStr = _amountStr.isEmpty ? '0.' : '$_amountStr.';
        }
      } else {
        // 数字
        if (_amountStr.contains('.')) {
          final parts = _amountStr.split('.');
          if (parts[1].length >= 2) return;
        }
        if (_amountStr == '0') {
          _amountStr = k;
        } else if (_amountStr.length < 10) {
          _amountStr += k;
        }
      }
    });
  }

  void _onOperator(String op) {
    // 当前没有数字 → 仅修改待用操作符（让用户连按 + - 切换）
    if (_amountStr.isEmpty) {
      _pendingOp = op;
      return;
    }
    final v = double.tryParse(_amountStr);
    if (v == null) return;
    _terms.add(_Term(v, _pendingOp));
    _amountStr = '';
    _pendingOp = op;
  }

  /// 总金额格式化：整数不带小数，否则保留 2 位
  String _formatTotal() {
    final v = _total;
    if (v == 0 && _amountStr.isEmpty) return '0';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  void _backspace() {
    if (_amountStr.isNotEmpty) {
      _amountStr = _amountStr.substring(0, _amountStr.length - 1);
    } else if (_terms.isNotEmpty) {
      // 恢复上一段为可编辑状态
      final last = _terms.removeLast();
      _pendingOp = last.op;
      // 用字符串形式恢复（保留小数）
      final v = last.value;
      _amountStr = v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(2);
    } else {
      _pendingOp = '+';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
          picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  Future<void> _save() async {
    final amount = _total;
    if (amount <= 0) {
      _toast('请输入有效金额');
      return;
    }

    // ── 转账分支 ────────────────────────────────────────────────
    if (_isTransfer) {
      if (_selectedAccount == null) {
        _toast('请选择转出账户');
        return;
      }
      if (_toAccount == null) {
        _toast('请选择转入账户');
        return;
      }
      if (_selectedAccount!.id == _toAccount!.id) {
        _toast('转出和转入账户不能相同');
        return;
      }
      setState(() => _saving = true);
      try {
        await ApiService.transfer(
          fromAccountId: _selectedAccount!.id,
          toAccountId: _toAccount!.id,
          amount: amount,
          note: _noteCtrl.text.trim(),
        );
        if (!mounted) return;
        bumpRefresh();
        Navigator.pop(context, true);
      } catch (_) {
        _toast('转账失败，请重试');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    // ── 收/支分支 ───────────────────────────────────────────────
    if (_selectedCategory == null) {
      _toast('请选择分类');
      return;
    }
    if (_selectedAccount == null) {
      _toast('请选择账户');
      return;
    }

    setState(() => _saving = true);
    try {
      // 用所选账户所在账本的 DEK 加密 note（空备注也加密，避免泄露"是否填了"信号）
      final ledgerId = _selectedAccount!.ledgerId;
      final dekVer = KeyChain.instance.dekVersionOf(ledgerId) ?? 1;
      final noteCipher = KeyChain.instance.encryptText(
        ledgerId: ledgerId,
        plain: _noteCtrl.text.trim(),
      );

      if (widget.bill != null) {
        await ApiService.updateBill(
          widget.bill!.id,
          type: _type,
          amount: amount,
          categoryId: _selectedCategory!.id,
          accountId: _selectedAccount!.id,
          noteCipher: noteCipher,
          noteDekVer: dekVer,
          date: _date,
        );
      } else {
        await ApiService.createBill(
          type: _type,
          amount: amount,
          categoryId: _selectedCategory!.id,
          accountId: _selectedAccount!.id,
          noteCipher: noteCipher,
          noteDekVer: dekVer,
          date: _date,
        );
      }
      // 把这次用的分类提到"最近"最前（不阻塞返回）
      await RecentsService.add(_type, _selectedCategory!.id);
      if (!mounted) return;
      bumpRefresh();
      Navigator.pop(context, true);
    } catch (_) {
      _toast('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── 语音 / OCR 快捷输入 ───────────────────────────────────────
  Future<void> _openVoiceInput() async {
    if (!_loaded) return;
    final draft = await showModalBottomSheet<BillDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VoiceInputSheet(categories: _categories),
    );
    if (draft != null) _applyDraft(draft);
  }

  Future<void> _openOcrInput() async {
    if (!_loaded) return;
    final draft = await showModalBottomSheet<BillDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => OcrInputSheet(categories: _categories),
    );
    if (draft != null) _applyDraft(draft);
  }

  /// 把语音 / OCR 解析出来的 [BillDraft] 套进当前表单。
  /// - 切对应 tab（收 / 支）
  /// - 金额：清空 terms，按解析金额填回数字键盘
  /// - 分类：如果命中就替换；没命中保留当前选择
  /// - 备注：把原始文本追加到备注（已有内容时换行）
  void _applyDraft(BillDraft draft) {
    // 不允许把"转账"切走的人通过解析改成收/支 —— 但目前 _applyDraft 只在
    // widget.bill == null 时才会被触发，这里继续维持新建模式的两种类型
    setState(() {
      final wantIdx = draft.type == 'income' ? 1 : 0;
      if (_tabCtrl.index != wantIdx) {
        _tabCtrl.animateTo(wantIdx);
        _type = draft.type;
        _selectedCategory = _filteredCategories.isNotEmpty
            ? _filteredCategories.first
            : null;
      }

      // 金额：重置算式 + 用解析金额填字符串
      _terms.clear();
      _pendingOp = '+';
      final amt = draft.amount;
      if (amt != null && amt > 0) {
        _amountStr = amt == amt.truncateToDouble()
            ? amt.toInt().toString()
            : amt.toStringAsFixed(2);
      } else {
        _amountStr = '';
      }

      // 分类：命中才替换
      if (draft.category != null) {
        // 用 id 在 _categories 里再找一次，避免 Category 引用对不上
        final hit = _categories
            .where((c) => c.id == draft.category!.id)
            .firstOrNull;
        if (hit != null) _selectedCategory = hit;
      }

      // 备注：把原始文本接进去（同已有内容用空行隔开）
      final extra = draft.rawText.trim();
      if (extra.isNotEmpty) {
        final cur = _noteCtrl.text.trim();
        _noteCtrl.text = cur.isEmpty ? extra : '$cur\n$extra';
      }
    });

    // 给用户一个反馈
    final amt = draft.amount;
    if (amt == null) {
      _toast('没解析到金额，请手动输入');
    } else {
      _toast(
          '已填入 ¥${amt.toStringAsFixed(2)}${draft.category != null ? " · ${draft.category!.name}" : ""}');
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return '今天';
    if (day == yesterday) return '昨天';
    return DateFormat('M月d日').format(d);
  }

  @override
  void dispose() {
    _tabCtrl
      ..removeListener(_onTabChanged)
      ..dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 按类型给主色：支出 红 / 收入 绿 / 转账 主题色
  Color get _accentColor {
    switch (_type) {
      case 'expense':
        return AppColors.expense;
      case 'income':
        return AppColors.income;
      case 'transfer':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // 不用 resizeToAvoidBottomInset，让键盘固定贴底
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          _header(accentColor),
          Expanded(
            child: _loaded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _isTransfer
                            ? _transferPills(accentColor)
                            : Column(
                                children: [
                                  _pillRow(
                                    label: '分类',
                                    icon: _selectedCategory?.displayIcon ?? '📂',
                                    value: _selectedCategory?.fullName ?? '选择分类',
                                    accent: accentColor,
                                    onTap: _openCategoryPicker,
                                  ),
                                  const SizedBox(height: 8),
                                  _pillRow(
                                    label: '账户',
                                    icon: _selectedAccount?.typeEmoji ?? '💰',
                                    value: _selectedAccount?.name ?? '选择账户',
                                    accent: accentColor,
                                    onTap: _openAccountPicker,
                                  ),
                                ],
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          children: [
                            // 日期：单独一行（不需要太宽）
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _dateTile(),
                            ),
                            const SizedBox(height: 8),
                            // 备注：单独一行、占满宽度、支持多行
                            _noteTile(),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _numPad(accentColor),
                      SafeArea(
                        top: false,
                        child: const SizedBox(height: 4),
                      ),
                    ],
                  )
                : Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _header(Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: color,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.bill != null ? '编辑账单' : '记一笔',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                // 仅"新建"模式提供语音 / OCR 快捷入口（编辑模式藏起避免误覆盖）
                if (widget.bill == null) ...[
                  IconButton(
                    tooltip: '语音记账',
                    icon: const Icon(Icons.mic_none_rounded,
                        color: Colors.white, size: 22),
                    onPressed: _openVoiceInput,
                  ),
                  IconButton(
                    tooltip: '拍照记账',
                    icon: const Icon(Icons.document_scanner_outlined,
                        color: Colors.white, size: 21),
                    onPressed: _openOcrInput,
                  ),
                ] else
                  const SizedBox(width: 48),
              ]),
            ),
            TabBar(
              controller: _tabCtrl,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 15),
              tabs: [
                const Tab(text: '支出'),
                const Tab(text: '收入'),
                // 编辑现有账单时不显示"转账"页
                if (widget.bill == null) const Tab(text: '转账'),
              ],
            ),
            // Amount display
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('¥',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 24)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _formatTotal(),
                          style: TextStyle(
                            color: (_total == 0 && _amountStr.isEmpty)
                                ? Colors.white38
                                : Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!_isTransfer && _selectedCategory != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_selectedCategory!.icon ?? '📂',
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 4),
                            Text(_selectedCategory!.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      if (_isTransfer)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text('账户转账',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ]),
                        ),
                    ],
                  ),
                  // 算式（仅在多项时才显示）
                  if (_hasExpression)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 28),
                      child: Text(
                        _displayExpr,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pill row（分类/账户 选择按钮） ────────────────────────────
  Widget _pillRow({
    required String label,
    required String icon,
    required String value,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 6),
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text1),
              ),
            ),
            Icon(Icons.unfold_more_rounded,
                size: 18, color: AppColors.text3),
          ]),
        ),
      ),
    );
  }

  // ── Pickers ───────────────────────────────────────────────────
  Future<void> _openCategoryPicker() async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryPickerSheet(
        categories: _filteredCategories,
        selectedId: _selectedCategory?.id,
        type: _type,
      ),
    );
    if (result != null) {
      setState(() => _selectedCategory = result);
    }
    // 不管选没选，picker 里可能新建过分类 —— 顺手重拉一遍，让父级缓存与服务端对齐
    _reloadCategories();
  }

  Future<void> _reloadCategories() async {
    try {
      final res = await ApiService.getCategories();
      if (!mounted) return;
      final cats = (res['categories'] as List? ?? [])
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .toList();
      setState(() => _categories = cats);
    } catch (_) {}
  }

  Future<void> _openAccountPicker() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AccountPickerSheet(
        accounts: _accounts,
        selectedId: _selectedAccount?.id,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedAccount = result;
        // 如果转账模式下选了和 to 相同的账户，清空 to 以避免冲突
        if (_isTransfer && _toAccount?.id == result.id) {
          _toAccount = null;
        }
      });
    }
  }

  /// 转账"从"账户：用当前用户可用账户
  Future<void> _openTransferFromPicker() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AccountPickerSheet(
        accounts: _accounts,
        selectedId: _selectedAccount?.id,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedAccount = result;
        if (_toAccount?.id == result.id) _toAccount = null;
      });
    }
  }

  /// 转账"到"账户：账本下全部账户，按记账人分组
  Future<void> _openTransferToPicker() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TransferToPickerSheet(
        accounts: _allAccounts,
        excludeId: _selectedAccount?.id,
        selectedId: _toAccount?.id,
      ),
    );
    if (result != null) {
      setState(() => _toAccount = result);
    }
  }

  /// 转账模式：两条 pill = 转出 + 转入，中间一个交换按钮
  Widget _transferPills(Color accent) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(children: [
          _pillRow(
            label: '转出',
            icon: _selectedAccount?.typeEmoji ?? '💰',
            value: _selectedAccount?.name ?? '选择转出账户',
            accent: accent,
            onTap: _openTransferFromPicker,
          ),
          const SizedBox(height: 8),
          _pillRow(
            label: '转入',
            icon: _toAccount?.typeEmoji ?? '💰',
            value: _transferToLabel(),
            accent: accent,
            onTap: _openTransferToPicker,
          ),
        ]),
        Positioned(
          right: 22,
          child: GestureDetector(
            onTap: () {
              // 仅在双方都是自己可用账户时才允许直接交换
              // （转入可能是其他成员的账户，从转入到那里属于"代他人收"，
              //  不应作为"转出"的源）
              if (_toAccount == null) return;
              final canSwapTo = _accounts.any((a) => a.id == _toAccount!.id);
              if (!canSwapTo) {
                _toast('对方账户不能作为你的转出账户');
                return;
              }
              setState(() {
                final tmp = _selectedAccount;
                _selectedAccount = _toAccount;
                _toAccount = tmp;
              });
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 3),
              ),
              child: Icon(Icons.swap_vert_rounded,
                  color: AppColors.onPrimary, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  String _transferToLabel() {
    final a = _toAccount;
    if (a == null) return '选择转入账户';
    final ownerName = a.ownerDisplayName;
    if (a.isShared) return '${a.name} · 共享';
    // 自己的私人账户
    if (_accounts.any((m) => m.id == a.id)) return a.name;
    // 他人的私人账户：附带主人名
    if (ownerName != null && ownerName.isNotEmpty) {
      return '${a.name} · $ownerName';
    }
    return a.name;
  }

  // ── Category grid (旧版网格 - 保留 fallback, 实际未使用) ────
  // ignore: unused_element
  Widget _categoryGrid(Color color) {
    final cats = _filteredCategories;
    if (cats.isEmpty) {
      return SizedBox(
          height: 60,
          child: Center(
              child: Text('暂无分类', style: TextStyle(color: AppColors.text2))));
    }
    // 限制最多 2 行可见，超出纵向滚动 —— 避免挤掉下面的键盘
    return SizedBox(
      height: 150,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 4,
            crossAxisSpacing: 6,
            childAspectRatio: 0.85,
          ),
          itemCount: cats.length,
        itemBuilder: (_, i) {
          final c = cats[i];
          final sel = _selectedCategory?.id == c.id;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = c),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: sel ? color : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? color : AppColors.border,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(c.icon ?? '📂',
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: sel ? color : AppColors.text2,
                    fontWeight:
                        sel ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  // ── Account chips (旧版 - 保留 fallback, 实际未使用) ────
  // ignore: unused_element
  Widget _accountChips() {
    if (_accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('请先添加账户',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _accounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _accounts[i];
          final sel = _selectedAccount?.id == a.id;
          return ChoiceChip(
            label: Text('${a.typeEmoji} ${a.name}'),
            selected: sel,
            onSelected: (_) => setState(() => _selectedAccount = a),
            selectedColor: AppColors.primaryLight,
            backgroundColor: AppColors.surface,
            side: BorderSide(
                color: sel ? AppColors.primary : AppColors.border),
            labelStyle: TextStyle(
              color: sel ? AppColors.primary : AppColors.text1,
              fontSize: 13,
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          );
        },
      ),
    );
  }

  // ── Date tile ─────────────────────────────────────────────────
  Widget _dateTile() => GestureDetector(
        onTap: _pickDate,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined,
                color: AppColors.text2, size: 17),
            const SizedBox(width: 8),
            Text(_formatDate(_date),
                style: TextStyle(
                    fontSize: 14, color: AppColors.text1)),
          ]),
        ),
      );

  // ── Note tile ─────────────────────────────────────────────────
  Widget _noteTile() => TextField(
        controller: _noteCtrl,
        style: TextStyle(fontSize: 14, color: AppColors.text1),
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: '备注…  例如：和谁、为什么、明细',
          hintStyle:
              TextStyle(color: AppColors.text2, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, top: 2),
            child: Icon(Icons.edit_note_rounded,
                color: AppColors.text2, size: 20),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 0),
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.fromLTRB(4, 12, 12, 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      );

  // ── Numpad ────────────────────────────────────────────────────
  // 4 列 × 4 行：数字 + 操作符 + 等号 + 退格
  Widget _numPad(Color color) {
    const rows = [
      ['7', '8', '9', '+'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '⌫'],
      ['.', '0', '00', '✓'], // ✓ = 完成（保存）
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        children: rows
            .map((row) => Row(
                  children: row
                      .map((k) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: _numKey(k, color),
                            ),
                          ))
                      .toList(),
                ))
            .toList(),
      ),
    );
  }

  Widget _numKey(String k, Color color) {
    final isBackspace = k == '⌫';
    final isDone = k == '✓';
    final isPlusMinus = k == '+' || k == '-';
    final isOp = isPlusMinus || isDone;

    // 高亮当前"挂起"的操作符，让用户立刻看到自己点了哪个
    final isActiveOp = isPlusMinus &&
        _amountStr.isEmpty &&
        (_terms.isNotEmpty || _pendingOp != '+') &&
        _pendingOp == k;

    // 视觉分组：完成键用主色填满；激活操作符也用主色填满
    final Color bg;
    final Color fg;
    if (isDone || isActiveOp) {
      bg = color;
      fg = Colors.white;
    } else if (isOp || isBackspace) {
      bg = color.withOpacity(0.08);
      fg = color;
    } else {
      bg = AppColors.surface;
      fg = AppColors.text1;
    }

    Widget content;
    if (isBackspace) {
      content = Icon(Icons.backspace_outlined, size: 20, color: fg);
    } else if (isDone) {
      content = _saving
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: fg),
            )
          : Text('完成',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg));
    } else {
      content = Text(
        k == '00' ? '00' : k,
        style: TextStyle(
          fontSize: isOp ? 24 : 21,
          fontWeight: isOp ? FontWeight.w600 : FontWeight.w500,
          color: fg,
        ),
      );
    }

    return GestureDetector(
      onTap: _saving && isDone
          ? null
          : () {
              if (k == '00') {
                _onKey('0');
                _onKey('0');
              } else {
                _onKey(k);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 46,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: (isDone || isActiveOp)
              ? null
              : Border.all(color: AppColors.border),
        ),
        child: Center(child: content),
      ),
    );
  }

  // ignore: unused_element
  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text2)),
      );
}

/// 算式中的一项：数值 + 操作符（'+' / '-'）
class _Term {
  final double value;
  final String op;
  const _Term(this.value, this.op);
}

/// 新建分类的输入弹窗。
/// - parentId 为 null：新建一级分类
/// - parentId 非空：新建二级分类（type 必须与父一致，由 backend 校验）
/// 成功返回创建好的 [Category]，否则返回 null（取消）。
Future<Category?> _promptNewCategory({
  required BuildContext context,
  required String title,
  required String hint,
  required String type,
  required String? parentId,
  required String? parentName,
}) async {
  final nameCtrl = TextEditingController();
  final iconCtrl = TextEditingController();
  bool saving = false;
  String? errorMsg;

  // 给一些常用 emoji 让用户点
  final isExpense = type == 'expense';
  final suggested = isExpense
      ? ['🛒', '💼', '🍔', '🚗', '🏠', '🎉', '💊', '📚', '🎮', '✈️', '🐾', '💡']
      : ['💰', '🎁', '📈', '💼', '🧾', '🏦', '🪙', '💵', '🎯', '🎊'];

  return showDialog<Category?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parentName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '父分类：$parentName · ${isExpense ? '支出' : '收入'}',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '类型：${isExpense ? '支出' : '收入'}',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: '名称',
                  hintText: hint,
                  counterText: '',
                ),
                onChanged: (_) {
                  if (errorMsg != null) setLocal(() => errorMsg = null);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: iconCtrl,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '图标（emoji，选填）',
                  hintText: '比如：🛒',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Text('快速选择',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.text2)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggested
                    .map((e) => InkWell(
                          onTap: () =>
                              setLocal(() => iconCtrl.text = e),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: iconCtrl.text == e
                                  ? AppColors.primaryLight
                                  : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: iconCtrl.text == e
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Center(
                                child: Text(e,
                                    style: const TextStyle(fontSize: 18))),
                          ),
                        ))
                    .toList(),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(
                        color: AppColors.expense, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                saving ? null : () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setLocal(() => errorMsg = '请输入分类名');
                      return;
                    }
                    setLocal(() => saving = true);
                    try {
                      final res = await ApiService.createCategory(
                        name: name,
                        type: type,
                        icon: iconCtrl.text.trim().isEmpty
                            ? null
                            : iconCtrl.text.trim(),
                        parentId: parentId,
                      );
                      final raw = res['category'] as Map<String, dynamic>?;
                      if (raw == null) {
                        setLocal(() {
                          saving = false;
                          errorMsg = '创建失败';
                        });
                        return;
                      }
                      if (ctx.mounted) {
                        Navigator.pop(ctx, Category.fromJson(raw));
                      }
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        errorMsg = '创建失败，请重试';
                      });
                    }
                  },
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建'),
          ),
        ],
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────
//  分类选择器 - 双列布局：左侧父分类，右侧子分类
// ────────────────────────────────────────────────────────────
class _CategoryPickerSheet extends StatefulWidget {
  final List<Category> categories;
  final String? selectedId;
  final String type;
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
    required this.type,
  });
  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

/// 「最近」一级分类用的虚拟 id（不存数据库）
const String _recentParentId = '__recent__';

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  /// 完整分类副本（包含 widget.categories + 用户新建的）。
  /// 用本地副本，避免新建后还要关掉重新打开才能看到。
  late List<Category> _cats;

  /// 用户最近用过的分类（本地缓存，按当前 type 过滤后的 Category 列表）
  List<Category> _recents = [];

  /// 一级分类列表：[最近] + 真实根分类
  List<Category> get _parents {
    final roots = _cats.where((c) => c.isRoot).toList();
    return [
      Category(
        id: _recentParentId,
        name: '最近',
        type: widget.type,
        icon: '🕒',
        isSystem: true,
      ),
      ...roots,
    ];
  }

  /// 当前展示子分类的父 id
  String? _expandedParentId;

  @override
  void initState() {
    super.initState();
    _cats = List<Category>.from(widget.categories);
    // 默认选「最近」，如果是编辑模式（有 selectedId）就展开它的父级
    final sel = _cats.where((c) => c.id == widget.selectedId).firstOrNull;
    if (sel != null) {
      _expandedParentId = sel.parentId ?? sel.id;
    } else {
      _expandedParentId = _recentParentId;
    }
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final ids = await RecentsService.get(widget.type);
    if (!mounted) return;
    // 按记录顺序还原（最近的在前），过滤掉已不存在的
    final map = {for (final c in _cats) c.id: c};
    final list = <Category>[];
    for (final id in ids) {
      final c = map[id];
      if (c != null) list.add(c);
    }
    setState(() => _recents = list);
    // 如果最近为空且初始默认是 _recentParentId，自动切到第一个真实父级
    if (_recents.isEmpty && _expandedParentId == _recentParentId) {
      final firstReal = _cats.where((c) => c.isRoot).firstOrNull;
      if (firstReal != null) {
        setState(() => _expandedParentId = firstReal.id);
      }
    }
  }

  List<Category> _childrenOf(String parentId) =>
      _cats.where((c) => c.parentId == parentId).toList();

  /// "其他…" 排序到最后 — 与后端规则保持一致，本地新建插入也按这个排
  void _localSortInPlace() {
    bool isOther(String s) => s.startsWith('其他');
    _cats.sort((a, b) {
      final aPid = a.parentId ?? '';
      final bPid = b.parentId ?? '';
      if (aPid != bPid) {
        if (aPid.isEmpty) return -1;
        if (bPid.isEmpty) return 1;
        return aPid.compareTo(bPid);
      }
      final ao = isOther(a.name);
      final bo = isOther(b.name);
      if (ao != bo) return ao ? 1 : -1;
      if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
      return 0;
    });
  }

  /// 新建一级分类
  Future<void> _createParent() async {
    final created = await _promptNewCategory(
      context: context,
      title: '新建一级分类',
      hint: '比如：装修、副业、宠物用品',
      type: widget.type,
      parentId: null,
      parentName: null,
    );
    if (created != null) {
      setState(() {
        _cats.add(created);
        _localSortInPlace();
        _expandedParentId = created.id;
      });
    }
  }

  /// 新建二级分类（挂到 [parent] 下）
  Future<void> _createChild(Category parent) async {
    final created = await _promptNewCategory(
      context: context,
      title: '在「${parent.name}」下新建二级分类',
      hint: '比如：早茶、机油、保养',
      type: widget.type,
      parentId: parent.id,
      parentName: parent.name,
    );
    if (created != null) {
      setState(() {
        _cats.add(created);
        _localSortInPlace();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.6;
    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Text('选择分类',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          // Body：左父右子
          Expanded(
            child: Row(children: [
              // ───────── 父分类列表 (40%) ─────────
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.35,
                child: Container(
                  color: AppColors.bg,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    // 末尾多一项 "+ 新建一级分类"
                    itemCount: _parents.length + 1,
                    itemBuilder: (_, i) {
                      if (i == _parents.length) {
                        return InkWell(
                          onTap: _createParent,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            child: Row(children: [
                              Icon(Icons.add_rounded,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('新建一级分类',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ),
                        );
                      }
                      final p = _parents[i];
                      final selected = p.id == _expandedParentId;
                      return InkWell(
                        onTap: () =>
                            setState(() => _expandedParentId = p.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.surface
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(children: [
                            Text(p.icon ?? '📂',
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: selected
                                      ? AppColors.text1
                                      : AppColors.text2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!p.isSystem)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text('自建',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600)),
                              ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // ───────── 子分类网格 (60%) ─────────
              Expanded(
                child: _expandedParentId == null
                    ? Center(
                        child: Text('没有分类',
                            style: TextStyle(color: AppColors.text2)))
                    : _buildChildren(_expandedParentId!),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// 3 列、严格正方形的子分类网格。
  /// 用 [LayoutBuilder] 拿到外层真实可用宽度，把每格 height 显式钉成 width，
  /// 不再依赖 [childAspectRatio]（在某些嵌套约束下会被外层强制变形）。
  Widget _squareGrid({
    required List<Category> items,
    required String? selectedId,
  }) {
    const cross = 3;
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (ctx, c) {
        final cellW = (c.maxWidth - spacing * (cross - 1)) / cross;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // 显式钉死 height = width
            mainAxisExtent: cellW,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final cat = items[i];
            return _gridItemCard(
              icon: cat.displayIcon,
              name: cat.name,
              selected: cat.id == selectedId,
              isUser: !cat.isSystem,
              onTap: () => Navigator.pop(context, cat),
            );
          },
        );
      },
    );
  }

  Widget _buildChildren(String parentId) {
    // 「最近」是虚拟父分类，独立渲染
    if (parentId == _recentParentId) {
      return _buildRecents();
    }
    final children = _childrenOf(parentId);
    final parent = _parents.firstWhere((p) => p.id == parentId);
    final selectedId = widget.selectedId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      children: [
        // 第一项：选父分类本身
        _gridItem(
          icon: parent.icon ?? '📂',
          name: parent.name,
          sub: children.isEmpty ? '(无子分类)' : null,
          selected: parent.id == selectedId,
          onTap: () => Navigator.pop(context, parent),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Row(children: [
            Text(children.isEmpty ? '二级分类' : '细分',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            InkWell(
              onTap: () => _createChild(parent),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                child: Row(children: [
                  Icon(Icons.add_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text('新建',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
        ),
        if (children.isNotEmpty)
          _squareGrid(
            items: children,
            selectedId: selectedId,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text('暂无二级分类，点右上 + 新建',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2)),
            ),
          ),
      ],
    );
  }

  /// 「最近」面板：把最近用过的分类以子分类卡片样式平铺，便于一键选
  Widget _buildRecents() {
    if (_recents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🕒', style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(
              '记一笔之后，最近用过的分类会自动收到这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.text2, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              '左侧选一个分类开始',
              style:
                  TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
      );
    }
    final selectedId = widget.selectedId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('最近用过',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w500)),
        ),
        _squareGrid(items: _recents, selectedId: selectedId),
      ],
    );
  }

  Widget _gridItem({
    required String icon,
    required String name,
    String? sub,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primary
                            : AppColors.text1)),
                if (sub != null)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text2)),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.primary),
        ]),
      ),
    );
  }

  Widget _gridItemCard({
    required String icon,
    required String name,
    required bool selected,
    required VoidCallback onTap,
    bool isUser = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      // 用 Stack + Positioned.fill 让主卡片真正填满 GridView 给的方格
      // （不加 fill，Stack 会给 Container 松约束，Container 缩成 Column 内容高度 = 看起来变成"长方形"）
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryLight
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? AppColors.primary
                            : AppColors.text1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 3, vertical: 0),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('自建',
                    style: TextStyle(
                        fontSize: 8,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  账户选择器 - 单列列表（适合任意数量账户）
// ────────────────────────────────────────────────────────────
class _AccountPickerSheet extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedId;
  const _AccountPickerSheet({
    required this.accounts,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final mine   = accounts.where((a) => !a.isShared).toList();
    final shared = accounts.where((a) => a.isShared).toList();
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Text('选择账户',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                if (mine.isNotEmpty) _sectionHead('我的账户', mine.length),
                ...mine.map((a) => _accountTile(context, a)),
                if (shared.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _sectionHead('共享账户', shared.length, hint: '账本成员共用'),
                ],
                ...shared.map((a) => _accountTile(context, a)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHead(String title, int count, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 4, 6),
        child: Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          const SizedBox(width: 6),
          Text('· $count',
              style: TextStyle(fontSize: 11, color: AppColors.text3)),
          if (hint != null) ...[
            const Spacer(),
            Text(hint,
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ]),
      );

  Widget _accountTile(BuildContext context, Account a) {
    final sel = a.id == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => Navigator.pop(context, a),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? AppColors.primary : AppColors.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(a.typeEmoji,
                      style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(a.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1)),
                    ),
                    if (a.isShared) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('共享',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(a.typeLabel,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ],
              ),
            ),
            Text('¥${a.balance.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(width: 8),
            if (sel)
              Icon(Icons.check_circle_rounded,
                  size: 18, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  转账目的地选择器 - 账本下全部账户，按记账人分组
//  - 共享账户为一组
//  - 每个成员的私人账户单独一组
//  - 不显示其他成员账户余额（隐私）
//  - 排除"转出账户"自身
// ────────────────────────────────────────────────────────────
class _TransferToPickerSheet extends StatelessWidget {
  final List<Account> accounts;
  final String? excludeId;
  final String? selectedId;
  const _TransferToPickerSheet({
    required this.accounts,
    required this.excludeId,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    final filtered =
        accounts.where((a) => a.id != excludeId).toList();

    // ── 分组：共享 / 各成员的私人账户 ─────────────────────────
    final shared = filtered.where((a) => a.isShared).toList();
    // 按 ownerId 聚合，ownerId 为 null 的已被 shared 拿走
    final byOwner = <String, List<Account>>{};
    final ownerDisplayCache = <String, String>{};
    for (final a in filtered) {
      if (a.isShared) continue;
      final oid = a.ownerId ?? '';
      byOwner.putIfAbsent(oid, () => []).add(a);
      ownerDisplayCache[oid] =
          a.ownerDisplayName ?? '（未知用户）';
    }
    // owner 排序：把"我"放最前（我没有 ownerName/balanceVisible=true 可用作判断）
    final ownerIds = byOwner.keys.toList();
    ownerIds.sort((a, b) {
      bool meA = (byOwner[a]?.first.balanceVisible ?? false);
      bool meB = (byOwner[b]?.first.balanceVisible ?? false);
      if (meA != meB) return meA ? -1 : 1;
      return ownerDisplayCache[a]!.compareTo(ownerDisplayCache[b]!);
    });

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Text('选择转入账户',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(width: 6),
              Text('· 账本全部',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text3)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                if (shared.isNotEmpty) ...[
                  _head('共享账户', shared.length, hint: '成员共用'),
                  ...shared.map((a) =>
                      _tile(context, a, ownerLabel: null)),
                  const SizedBox(height: 4),
                ],
                for (final oid in ownerIds) ...[
                  _head(
                    // 自己的账户显示"我的账户"，其他成员显示昵称/用户名
                    (byOwner[oid]?.first.balanceVisible ?? false)
                        ? '我的账户'
                        : '${ownerDisplayCache[oid]} 的账户',
                    byOwner[oid]!.length,
                    hint: (byOwner[oid]?.first.balanceVisible ?? false)
                        ? null
                        : '私人',
                  ),
                  ...byOwner[oid]!.map((a) => _tile(
                        context,
                        a,
                        // 同行不再重复主人名
                        ownerLabel: null,
                      )),
                  const SizedBox(height: 4),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('账本下没有其他账户',
                          style: TextStyle(color: AppColors.text2)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _head(String title, int count, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 4, 6),
        child: Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          const SizedBox(width: 6),
          Text('· $count',
              style: TextStyle(fontSize: 11, color: AppColors.text3)),
          if (hint != null) ...[
            const Spacer(),
            Text(hint,
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ]),
      );

  Widget _tile(BuildContext context, Account a, {String? ownerLabel}) {
    final sel = a.id == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => Navigator.pop(context, a),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? AppColors.primary : AppColors.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(a.typeEmoji,
                      style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(height: 2),
                  Text(a.typeLabel,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ],
              ),
            ),
            if (a.balanceVisible)
              Text('¥${a.balance.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1))
            else
              Text('—',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.text3)),
            const SizedBox(width: 8),
            if (sel)
              Icon(Icons.check_circle_rounded,
                  size: 18, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}
