import 'package:flutter/material.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../services/api_service.dart';

/// 账户间转账底部弹窗
class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.accounts});
  final List<Account> accounts;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  Account? _from;
  Account? _to;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.accounts.length >= 2) {
      _from = widget.accounts.first;
      _to = widget.accounts[1];
    } else if (widget.accounts.length == 1) {
      _from = widget.accounts.first;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _swap() {
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    });
  }

  Future<void> _save() async {
    if (_from == null || _to == null) {
      _toast('请选择账户');
      return;
    }
    if (_from!.id == _to!.id) {
      _toast('转出和转入账户不能相同');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _toast('请输入有效金额');
      return;
    }

    setState(() => _saving = true);
    try {
      // 生成两条转账流水的备注密文（用账本 DEK 客户端加密）。
      // 密钥未就绪时降级为仅改余额（不留流水），转账本身仍成功。
      final userNote = _noteCtrl.text.trim();
      final tail = userNote.isEmpty ? '' : ' · $userNote';
      final lid = _from!.ledgerId;
      String? fromCipher, toCipher;
      int? dekVer;
      if (KeyChain.instance.hasDek(lid)) {
        dekVer = KeyChain.instance.dekVersionOf(lid) ?? 1;
        fromCipher = KeyChain.instance.encryptText(
            ledgerId: lid, plain: '转账·转出 → ${_to!.name}$tail');
        toCipher = KeyChain.instance.encryptText(
            ledgerId: lid, plain: '转账·转入 ← ${_from!.name}$tail');
      }
      await ApiService.transfer(
        fromAccountId: _from!.id,
        toAccountId: _to!.id,
        amount: amount,
        note: userNote,
        fromNoteCipher: fromCipher,
        toNoteCipher: toCipher,
        noteDekVer: dekVer,
      );
      if (!mounted) return;
      bumpRefresh();
      Navigator.pop(context);
    } catch (_) {
      _toast('转账失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 16),
          Text('账户转账',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text1)),
          const SizedBox(height: 4),
          Text('账户之间转账不影响收支统计',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
          const SizedBox(height: 20),
          // From → To
          Stack(
            alignment: Alignment.center,
            children: [
              Column(children: [
                _accountTile('从', _from,
                    onTap: () => _pickAccount(true)),
                const SizedBox(height: 10),
                _accountTile('到', _to,
                    onTap: () => _pickAccount(false), accent: true),
              ]),
              Positioned(
                child: GestureDetector(
                  onTap: _swap,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 3),
                    ),
                    child: Icon(Icons.swap_vert_rounded,
                        color: AppColors.onPrimary, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Amount
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '转账金额',
              prefixText: '¥ ',
            ),
          ),
          const SizedBox(height: 12),
          // Note
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: '备注（选填）',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary))
                  : const Text('确认转账',
                      style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTile(String label, Account? account,
      {required VoidCallback onTap, bool accent = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: accent ? AppColors.primary : AppColors.border,
              width: accent ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(account?.typeEmoji ?? '💰',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text2)),
                const SizedBox(height: 2),
                Text(
                  account?.name ?? '选择账户',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: account == null
                        ? AppColors.text2
                        : AppColors.text1,
                  ),
                ),
              ],
            ),
          ),
          if (account != null)
            Text(
              fmtMoney(account.balance),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.text2),
        ]),
      ),
    );
  }

  Future<void> _pickAccount(bool isFrom) async {
    final picked = await showModalBottomSheet<Account>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 16),
            Text(isFrom ? '选择转出账户' : '选择转入账户',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...widget.accounts.map((a) => ListTile(
                  onTap: () => Navigator.pop(context, a),
                  leading: Text(a.typeEmoji,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(a.name),
                  subtitle: Text(a.typeLabel,
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text(fmtMoney(a.balance),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                )),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
          if (_to?.id == picked.id) _to = null;
        } else {
          _to = picked;
          if (_from?.id == picked.id) _from = null;
        }
      });
    }
  }
}
