import 'package:flutter/material.dart';

import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'siku_ui.dart';

/// 对话记账草稿卡（从 chat_screen 抽出复用：司库助手对话 + 语音记账共用）。
/// 备注明文只在此卡片里（瞬时，不落库）。
/// 用户点「确认」时，客户端加密备注 + 调 createBill 真正记账。
class BillDraftCard extends StatefulWidget {
  const BillDraftCard({super.key, required this.data, this.onDone});

  /// bill_draft 卡片数据：amount / categoryId / categoryName /
  /// accountName? / note / billType('expense'|'income')
  final Map<String, dynamic> data;

  /// 确认入库成功后回调（如语音记账弹层借此自动关闭）
  final VoidCallback? onDone;

  @override
  State<BillDraftCard> createState() => _BillDraftCardState();
}

class _BillDraftCardState extends State<BillDraftCard> {
  String _state = 'pending'; // pending|done|cancelled
  bool _busy = false;

  double get _amount => ((widget.data['amount'] as num?) ?? 0).toDouble();
  String get _categoryId => (widget.data['categoryId'] as String?) ?? '';
  String get _categoryName => (widget.data['categoryName'] as String?) ?? '';
  String get _accountName =>
      ((widget.data['accountName'] as String?) ?? '').trim();
  String get _note => (widget.data['note'] as String?) ?? '';
  String get _billType =>
      (widget.data['billType'] as String?) == 'income' ? 'income' : 'expense';

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _confirm() async {
    if (_categoryId.isEmpty) {
      _toast('分类缺失');
      return;
    }
    setState(() => _busy = true);
    try {
      final lid = await AuthService.getCurrentLedgerId();
      if (lid == null || !KeyChain.instance.hasDek(lid)) {
        _toast('账本密钥未就绪');
        if (mounted) setState(() => _busy = false);
        return;
      }

      // 取账户（客户端用 DEK 解密名字后匹配）
      final accRes = await ApiService.getAccounts();
      final accounts = (accRes['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      if (accounts.isEmpty) {
        _toast('请先创建账户');
        if (mounted) setState(() => _busy = false);
        return;
      }
      // 指定了账户名→按解密名包含匹配；否则/匹配不到→用第一个账户
      Account? acc;
      if (_accountName.isNotEmpty) {
        for (final a in accounts) {
          if (a.name.contains(_accountName)) {
            acc = a;
            break;
          }
        }
      }
      acc ??= accounts.first;

      final dekVer = KeyChain.instance.dekVersionOf(lid) ?? 1;
      // 备注可能为空——空字符串也加密（与 app 其他处一致）
      final cipher = KeyChain.instance.encryptText(ledgerId: lid, plain: _note);

      await ApiService.createBill(
        type: _billType,
        amount: _amount,
        categoryId: _categoryId,
        accountId: acc.id,
        noteCipher: cipher,
        noteDekVer: dekVer,
        date: DateTime.now(),
      );
      bumpRefresh();
      if (mounted) {
        setState(() {
          _state = 'done';
          _busy = false;
        });
        _toast('✅ 已记一笔');
        widget.onDone?.call();
      }
    } catch (_) {
      if (mounted) {
        _toast('记账失败');
        setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    // 没有创建任何东西，纯本地标记取消
    setState(() => _state = 'cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final acc = _accountName;
    final note = _note.trim();
    final parts = <String>[
      '¥${formatAmount(_amount)}',
      _categoryName,
      if (acc.isNotEmpty) acc,
      if (note.isNotEmpty) note,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '记一笔 · ${parts.join(' · ')}',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text1),
        ),
        const SizedBox(height: 12),
        if (_state == 'pending')
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? '处理中…' : '确认'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: _busy ? null : _cancel, child: const Text('取消')),
          ])
        else
          Text(_state == 'done' ? '✅ 已记一笔' : '已取消',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
      ]),
    );
  }
}
