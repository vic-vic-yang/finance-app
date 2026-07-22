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

  /// 自动执行规则：actionType -> enabled（未建记录视为 false）
  Map<String, bool> _autoRules = {};
  final Set<String> _ruleBusy = {};

  /// 可自动化的动作类型（与后端白名单一致；高危动作永不在此列）
  static const _ruleMeta = <String, (String, String)>{
    'adjust_budget': ('调整预算', '超支预警给出的调额建议自动生效'),
    'recategorize_bill': ('智能改分类', '明显错分的账单自动归入正确分类'),
  };

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
    try {
      final rules = await ApiService.cfoAutoRules();
      if (rules is List) {
        _autoRules = {
          for (final r in rules)
            if (r is Map && r['actionType'] is String)
              r['actionType'] as String: r['enabled'] == true,
        };
      }
    } catch (_) {
      /* 规则加载失败不阻塞提议列表 */
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleRule(String actionType, bool enabled) async {
    setState(() {
      _ruleBusy.add(actionType);
      _autoRules[actionType] = enabled; // 乐观更新
    });
    try {
      await ApiService.cfoSetAutoRule(actionType, enabled);
    } catch (_) {
      if (mounted) {
        setState(() => _autoRules[actionType] = !enabled); // 失败回滚
        _toast('设置失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _ruleBusy.remove(actionType));
    }
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
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _autoRulesCard(),
                    const SizedBox(height: 12),
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: EmptyState(
                            emoji: '✅', title: '目前一切正常', top: 0),
                      )
                    else
                      ..._items.map(_card),
                  ],
                ),
              ),
      ),
    );
  }

  /// 「自动执行」区块：白名单动作开关 + 留痕说明
  Widget _autoRulesCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('自动执行',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 4),
        Text('低风险提议将自动执行并在此留痕，高危操作永远需要你确认',
            style: TextStyle(fontSize: 12, color: AppColors.text3)),
        const SizedBox(height: 8),
        for (final entry in _ruleMeta.entries) ...[
          _ruleRow(entry.key, entry.value.$1, entry.value.$2),
          if (entry.key != _ruleMeta.keys.last)
            Divider(height: 1, color: AppColors.border),
        ],
      ]),
    );
  }

  Widget _ruleRow(String actionType, String label, String desc) {
    final enabled = _autoRules[actionType] ?? false;
    final busy = _ruleBusy.contains(actionType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text1)),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 12, color: AppColors.text2)),
          ]),
        ),
        Opacity(
          opacity: busy ? 0.5 : 1,
          child: Switch(
            value: enabled,
            onChanged: busy ? null : (v) => _toggleRule(actionType, v),
          ),
        ),
      ]),
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
          if (p.autoExecuted) _autoBadge(),
        ]),
        const SizedBox(height: 6),
        Text(p.body, style: TextStyle(fontSize: 13, color: AppColors.text2)),
        if (!p.autoExecuted) ...[
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
        ],
      ]),
    );
  }

  /// 「已自动执行」留痕标识：主色浅底小胶囊
  Widget _autoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bolt_rounded, size: 12, color: AppColors.primary),
        const SizedBox(width: 2),
        Text('已自动执行',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
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
