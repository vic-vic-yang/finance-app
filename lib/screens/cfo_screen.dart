import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/refresh_bus.dart';
import '../crypto/key_chain.dart';
import '../models/proposal.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/siku_ui.dart';
import 'recategorize_other_screen.dart';

class CfoScreen extends StatefulWidget {
  const CfoScreen({super.key});
  @override
  State<CfoScreen> createState() => _CfoScreenState();
}

class _CfoScreenState extends State<CfoScreen> {
  bool _loading = true;
  List<Proposal> _items = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.cfoProposals();
      // 后端正常返回 List；兜底处理被包成 Map 的情况。
      final list = (res is List
          ? res
          : (res is Map
              ? (res['proposals'] ?? res['data'] ?? const [])
              : const [])) as List;
      _items = list
          .map((e) => Proposal.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      /* 保持空 */
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(Proposal p, String action) async {
    setState(() => _busy.add(p.id));
    try {
      // 客户端协助动作：approve 时先用既有 API 完成真实动作，再 resolve
      if (action == 'approve' && p.requiresClient) {
        final ok = await _runClientAction(p);
        if (!ok) {
          setState(() => _busy.remove(p.id));
          return;
        }
        await ApiService.cfoDecide(p.id, 'resolve');
      } else {
        await ApiService.cfoDecide(p.id, action);
      }
      setState(() => _items.removeWhere((x) => x.id == p.id));
      bumpRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// 客户端协助动作：用既有 API 完成真实动作，返回是否已完成。
  Future<bool> _runClientAction(Proposal p) async {
    final params = p.actionParams;
    if (p.actionKind == 'allocate_to_goal') {
      final lid = await AuthService.getCurrentLedgerId();
      if (lid == null || !KeyChain.instance.hasDek(lid)) {
        _toast('账本密钥未就绪');
        return false;
      }
      final dekVer = KeyChain.instance.dekVersionOf(lid) ?? 1;
      final amount = (params['amount'] as num).toDouble();
      // 备注用通用文案（账户/目标名是加密的，这里不取明文）
      final fromCipher =
          KeyChain.instance.encryptText(ledgerId: lid, plain: '转账·转出 → 储蓄目标');
      final toCipher =
          KeyChain.instance.encryptText(ledgerId: lid, plain: '转账·转入 ← 闲钱归集');
      await ApiService.transfer(
        fromAccountId: params['fromAccountId'] as String,
        toAccountId: params['toAccountId'] as String,
        amount: amount,
        fromNoteCipher: fromCipher,
        toNoteCipher: toCipher,
        noteDekVer: dekVer,
      );
      return true;
    }
    if (p.actionKind == 'review_uncategorized') {
      // 只列出"其他"分类账单，逐笔改分类
      final ids =
          ((params['categoryIds'] as List?) ?? const []).cast<String>();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => RecategorizeOtherScreen(categoryIds: ids)),
        );
      }
      return true;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '复盘'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(
                    child: EmptyState(
                        emoji: '✅', title: '目前一切正常', top: 0))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _card(_items[i]),
                    ),
                  ),
      ),
    );
  }

  // 与首页洞察一致：critical=哑红、warning=琥珀、info=主题色
  Color _sevColor(String s) => s == 'critical'
      ? AppColors.income
      : (s == 'info' ? AppColors.primary : AppColors.warning);

  Widget _card(Proposal p) {
    final busy = _busy.contains(p.id);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: _sevColor(p.severity), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(p.title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1))),
        ]),
        const SizedBox(height: 6),
        Text(p.body, style: TextStyle(fontSize: 13, color: AppColors.text2)),
        const SizedBox(height: 10),
        // 操作行：小胶囊（同意=实心主色，稍后/忽略=ghost），克制不占版面
        Row(children: [
          _pill(
            busy ? '处理中…' : '同意',
            filled: true,
            onTap: busy ? null : () => _decide(p, 'approve'),
          ),
          const SizedBox(width: 8),
          _pill('稍后', onTap: busy ? null : () => _decide(p, 'snooze')),
          const SizedBox(width: 8),
          _pill('忽略', onTap: busy ? null : () => _decide(p, 'dismiss')),
        ]),
      ]),
    );
  }

  /// 小胶囊按钮：filled=主色实心（主操作），否则描边 ghost（次操作）
  Widget _pill(String label, {bool filled = false, VoidCallback? onTap}) {
    final enabled = onTap != null;
    final color = filled ? AppColors.onPrimary : AppColors.text2;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: filled ? null : Border.all(color: AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      ),
    );
  }
}
