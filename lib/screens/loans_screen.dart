import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/refresh_bus.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/loan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/glass.dart';
import 'add_bill_screen.dart' show AccountPickerSheet;

/// 借贷往来：别人欠我(应收) / 我欠别人(应付)，可记借出/借入、还款、上传凭证。
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  List<Loan> _loans = [];
  List<Account> _accounts = [];
  double _receivable = 0;
  double _payable = 0;
  String _ledgerId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _ledgerId = await AuthService.getCurrentLedgerId() ?? '';
    // 三个请求各自独立：即便借贷接口暂时不可用，账户列表也要能加载，
    // 否则记一笔时账户选择器会空白。
    await Future.wait([
      _loadLoans(),
      _loadSummary(),
      _loadAccounts(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLoans() async {
    try {
      final list = await ApiService.getLoans();
      _loans = list
          .map((e) => Loan.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {}
  }

  Future<void> _loadSummary() async {
    try {
      final sum = await ApiService.getLoanSummary();
      _receivable = (sum['receivable'] as num?)?.toDouble() ?? 0;
      _payable = (sum['payable'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await ApiService.getAccounts();
      _accounts = (res['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  List<Loan> get _lend => _loans.where((l) => l.isLend).toList();
  List<Loan> get _borrow => _loans.where((l) => !l.isLend).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '借贷往来'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _summaryCard(),
                    const SizedBox(height: 16),
                    if (_lend.isNotEmpty) ...[
                      _sectionTitle('别人欠我（应收）', _lend.length),
                      for (final l in _lend) _loanTile(l),
                      const SizedBox(height: 8),
                    ],
                    if (_borrow.isNotEmpty) ...[
                      _sectionTitle('我欠别人（应付）', _borrow.length),
                      for (final l in _borrow) _loanTile(l),
                    ],
                    if (_loans.isEmpty) _empty(),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('记一笔借贷'),
        shape: const StadiumBorder(),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Column(children: [
            const Text('🤝', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text('还没有借贷记录',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text('点右下角「记一笔借贷」，记下借出/借入，写个备注、传张转账凭证就行。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.text2, height: 1.6)),
            ),
          ]),
        ),
      );

  Widget _summaryCard() {
    final net = _receivable - _payable;
    final fg = AppColors.onPrimaryGradient;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('净往来（应收 − 应付）',
              style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
          const SizedBox(height: 4),
          Text('${net >= 0 ? '' : '-'}¥${net.abs().toStringAsFixed(2)}',
              style: TextStyle(
                  color: fg,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.8)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _sumItem('别人欠我', _receivable, fg)),
            Container(width: 1, height: 28, color: fg.withOpacity(0.2)),
            Expanded(child: _sumItem('我欠别人', _payable, fg)),
          ]),
        ],
      ),
    );
  }

  Widget _sumItem(String label, double v, Color fg) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11.5)),
            const SizedBox(height: 3),
            Text('¥${v.toStringAsFixed(2)}',
                style: TextStyle(
                    color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _sectionTitle(String t, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Row(children: [
          Text(t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          const SizedBox(width: 6),
          Text('· $n', style: TextStyle(fontSize: 12, color: AppColors.text3)),
        ]),
      );

  Widget _loanTile(Loan l) {
    final note = l.noteOf(_ledgerId);
    final color = l.isLend ? AppColors.income : AppColors.expense;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _openDetail(l),
      child: Row(children: [
        if (l.voucherKey != null) ...[
          _VoucherThumb(voucherKey: l.voucherKey!, size: 44),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.isEmpty ? (l.isLend ? '借出' : '借入') : note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(height: 3),
              Row(children: [
                Text(DateFormat('M月d日').format(l.date),
                    style: TextStyle(fontSize: 12, color: AppColors.text3)),
                const SizedBox(width: 8),
                if (l.settled)
                  _chip('已结清', AppColors.text3)
                else if (l.repaidAmount > 0)
                  _chip('已${l.isLend ? '收' : '还'} ¥${l.repaidAmount.toStringAsFixed(0)}',
                      AppColors.warning)
                else
                  _chip(l.isLend ? '未收' : '未还', color),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${l.isLend ? '+' : '-'}¥${l.amount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            if (!l.settled && l.repaidAmount > 0)
              Text('剩 ¥${l.outstanding.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: c.withOpacity(0.13),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(t,
            style:
                TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c)),
      );

  // ── 新增借贷 ──────────────────────────────────────────────
  Future<void> _openCreate() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LoanSheet(
        ledgerId: _ledgerId,
        accounts: _accounts,
      ),
    );
    if (ok == true) {
      bumpRefresh();
      _load();
    }
  }

  // ── 详情 / 还款 ───────────────────────────────────────────
  Future<void> _openDetail(Loan l) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LoanDetailSheet(
        loan: l,
        ledgerId: _ledgerId,
        accounts: _accounts,
      ),
    );
    if (ok == true) {
      bumpRefresh();
      _load();
    }
  }
}

/// 凭证缩略图（带鉴权拉取）
class _VoucherThumb extends StatefulWidget {
  const _VoucherThumb({required this.voucherKey, this.size = 44});
  final String voucherKey;
  final double size;
  @override
  State<_VoucherThumb> createState() => _VoucherThumbState();
}

class _VoucherThumbState extends State<_VoucherThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    ApiService.fetchVoucher(widget.voucherKey).then((b) {
      if (mounted && b != null) setState(() => _bytes = Uint8List.fromList(b));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: AppColors.surfaceAlt,
        child: _bytes == null
            ? Icon(Icons.image_outlined, size: 18, color: AppColors.text3)
            : Image.memory(_bytes!, fit: BoxFit.cover),
      ),
    );
  }
}

/// 新增借出/借入弹层
class _LoanSheet extends StatefulWidget {
  const _LoanSheet({required this.ledgerId, required this.accounts});
  final String ledgerId;
  final List<Account> accounts;
  @override
  State<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<_LoanSheet> {
  int _dir = 0; // 0=借出 1=借入
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Account? _account;
  DateTime _date = DateTime.now();
  String? _voucherKey;
  Uint8List? _voucherPreview;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) _account = widget.accounts.first;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVoucher() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final f = res?.files.first;
    if (f?.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final up = await ApiService.uploadVoucher(f!.bytes!, f.name);
      if (!mounted) return;
      setState(() {
        _voucherKey = up['key'] as String?;
        _voucherPreview = f.bytes;
        _uploading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('凭证上传失败')));
      }
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入金额')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? noteCipher;
      int? dekVer;
      if (KeyChain.instance.hasDek(widget.ledgerId)) {
        dekVer = KeyChain.instance.dekVersionOf(widget.ledgerId) ?? 1;
        noteCipher = KeyChain.instance.encryptText(
            ledgerId: widget.ledgerId, plain: _noteCtrl.text.trim());
      }
      await ApiService.createLoan(
        direction: _dir == 0 ? 'lend' : 'borrow',
        amount: amount,
        accountId: _account?.id,
        noteCipher: noteCipher,
        noteDekVer: dekVer,
        voucherKey: _voucherKey,
        date: _date,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('记一笔借贷',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 14),
            _seg(),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '金额', prefixText: '¥ '),
            ),
            const SizedBox(height: 12),
            _accountRow(),
            const SizedBox(height: 12),
            _dateRow(),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '备注',
                hintText: _dir == 0 ? '借给谁、约定还款…' : '向谁借、约定还款…',
              ),
            ),
            const SizedBox(height: 12),
            _voucherRow(),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg() {
    Widget item(int i, String label) {
      final sel = _dir == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _dir = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                    color: sel ? AppColors.onPrimary : AppColors.text2)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(children: [
        item(0, '借出（别人欠我）'),
        item(1, '借入（我欠别人）'),
      ]),
    );
  }

  Widget _accountRow() => InkWell(
        onTap: () async {
          final a = await showModalBottomSheet<Account>(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => AccountPickerSheet(
                accounts: widget.accounts, selectedId: _account?.id),
          );
          if (a != null) setState(() => _account = a);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Text(_dir == 0 ? '出款账户' : '入款账户',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const SizedBox(width: 12),
            Text(_account != null
                ? '${_account!.typeEmoji} ${_account!.name}'
                : '不关联账户',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text1)),
            const Spacer(),
            Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.text3),
          ]),
        ),
      );

  Widget _dateRow() => InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (d != null) setState(() => _date = d);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined,
                size: 17, color: AppColors.text2),
            const SizedBox(width: 10),
            Text(DateFormat('yyyy年M月d日').format(_date),
                style: TextStyle(fontSize: 14, color: AppColors.text1)),
          ]),
        ),
      );

  Widget _voucherRow() => Row(children: [
        if (_voucherPreview != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_voucherPreview!,
                width: 48, height: 48, fit: BoxFit.cover),
          )
        else
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.receipt_long_outlined,
                color: AppColors.text3, size: 20),
          ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickVoucher,
          icon: _uploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_rounded, size: 18),
          label: Text(_voucherKey == null ? '上传转账凭证' : '已上传，重新选'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]);
}

/// 借贷详情 + 还款弹层
class _LoanDetailSheet extends StatefulWidget {
  const _LoanDetailSheet({
    required this.loan,
    required this.ledgerId,
    required this.accounts,
  });
  final Loan loan;
  final String ledgerId;
  final List<Account> accounts;
  @override
  State<_LoanDetailSheet> createState() => _LoanDetailSheetState();
}

class _LoanDetailSheetState extends State<_LoanDetailSheet> {
  final _repayCtrl = TextEditingController();
  Account? _account;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repayCtrl.text = widget.loan.outstanding.toStringAsFixed(2);
    _account = widget.accounts.firstWhere(
      (a) => a.id == widget.loan.accountId,
      orElse: () =>
          widget.accounts.isNotEmpty ? widget.accounts.first : _dummy(),
    );
    if (widget.accounts.isEmpty) _account = null;
  }

  Account _dummy() => Account(
      id: '', ledgerId: '', nameCipher: null, type: 'CASH', balance: 0);

  @override
  void dispose() {
    _repayCtrl.dispose();
    super.dispose();
  }

  Future<void> _repay() async {
    final amount = double.tryParse(_repayCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    setState(() => _busy = true);
    try {
      await ApiService.repayLoan(widget.loan.id,
          amount: amount, accountId: _account?.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除借贷记录'),
        content: const Text('只删记录，已产生的账户流水保留。确定？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除', style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ApiService.deleteLoan(widget.loan.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    final note = l.noteOf(widget.ledgerId);
    final color = l.isLend ? AppColors.income : AppColors.expense;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(l.isLend ? '别人欠我' : '我欠别人',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2)),
              const Spacer(),
              IconButton(
                onPressed: _busy ? null : _delete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: AppColors.text3, size: 20),
              ),
            ]),
            Text('${l.isLend ? '+' : '-'}¥${l.amount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(
                '${DateFormat('yyyy年M月d日').format(l.date)}'
                '${l.repaidAmount > 0 ? '   已${l.isLend ? '收' : '还'} ¥${l.repaidAmount.toStringAsFixed(2)}' : ''}'
                '${l.settled ? '   · 已结清' : '   · 剩 ¥${l.outstanding.toStringAsFixed(2)}'}',
                style: TextStyle(fontSize: 12.5, color: AppColors.text3)),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(note,
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: AppColors.text1)),
            ],
            if (l.voucherKey != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _viewVoucher(l.voucherKey!),
                child: _VoucherThumb(voucherKey: l.voucherKey!, size: 120),
              ),
            ],
            if (!l.settled) ...[
              const Divider(height: 28),
              Text(l.isLend ? '记一笔收款' : '记一笔还款',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(height: 10),
              TextField(
                controller: _repayCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '金额', prefixText: '¥ '),
              ),
              const SizedBox(height: 10),
              if (widget.accounts.isNotEmpty)
                InkWell(
                  onTap: () async {
                    final a = await showModalBottomSheet<Account>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => AccountPickerSheet(
                          accounts: widget.accounts,
                          selectedId: _account?.id),
                    );
                    if (a != null) setState(() => _account = a);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Text(l.isLend ? '收款到' : '从账户还',
                          style:
                              TextStyle(fontSize: 13, color: AppColors.text2)),
                      const SizedBox(width: 12),
                      Text(
                          (_account != null && _account!.id.isNotEmpty)
                              ? '${_account!.typeEmoji} ${_account!.name}'
                              : '不关联账户',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.text1)),
                      const Spacer(),
                      Icon(Icons.unfold_more_rounded,
                          size: 18, color: AppColors.text3),
                    ]),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _repay,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(l.isLend ? '确认收款' : '确认还款'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewVoucher(String key) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: _VoucherFull(voucherKey: key),
        ),
      ),
    );
  }
}

/// 凭证大图
class _VoucherFull extends StatefulWidget {
  const _VoucherFull({required this.voucherKey});
  final String voucherKey;
  @override
  State<_VoucherFull> createState() => _VoucherFullState();
}

class _VoucherFullState extends State<_VoucherFull> {
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    ApiService.fetchVoucher(widget.voucherKey).then((b) {
      if (mounted && b != null) setState(() => _bytes = Uint8List.fromList(b));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _bytes == null
        ? const SizedBox(
            height: 200, child: Center(child: CircularProgressIndicator()))
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(child: Image.memory(_bytes!)));
  }
}
