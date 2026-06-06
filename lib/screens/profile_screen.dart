import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/theme_service.dart';
import '../core/refresh_bus.dart';
import '../core/app_version.dart';
import '../core/update_checker.dart';
import '../crypto/crypto_bootstrap.dart';
import '../crypto/key_chain.dart';
import '../models/ledger.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/glass.dart';
import 'accounts_screen.dart';
import 'ai_imports_screen.dart';
import 'bills_screen.dart';
import 'chat_screen.dart';
import 'monthly_report_screen.dart';
import 'recurring_screen.dart';
import 'ledgers_screen.dart';
import 'tools/tools_screen.dart';
import 'news_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _username = '';
  String? _nickname;
  Ledger? _currentLedger;
  int _ledgerCount = 1;

  /// 显示名：昵称优先，否则用户名
  String get _displayName {
    final n = (_nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return _username;
  }

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

  Future<void> _load() async {
    final user = await AuthService.getUser();
    if (mounted) {
      setState(() {
        _username = user?['username'] ?? '';
        _nickname = user?['nickname'] as String?;
      });
    }
    // 后台拉一次最新资料（其他端可能改过昵称）
    try {
      final me = await ApiService.getMe();
      final u = me['user'] as Map<String, dynamic>?;
      if (u != null && mounted) {
        setState(() {
          _username = u['username'] as String? ?? _username;
          _nickname = u['nickname'] as String?;
        });
        final cur = await AuthService.getUser() ?? {};
        cur['username'] = u['username'];
        cur['nickname'] = u['nickname'];
        cur['id'] = u['id'];
        await AuthService.saveUser(cur);
      }
    } catch (_) {}
    try {
      final res = await ApiService.getLedgers();
      if (!mounted) return;
      final all = (res['ledgers'] as List? ?? [])
          .map((l) => Ledger.fromJson(l as Map<String, dynamic>))
          .toList();
      final currentId = res['currentLedgerId'] as String?;
      setState(() {
        _ledgerCount = all.length;
        _currentLedger = all.firstWhere(
          (l) => l.id == currentId,
          orElse: () => all.isNotEmpty
              ? all.first
              : Ledger(
                  id: '',
                  name: '我的账本',
                  isPersonal: true,
                  ownerId: '',
                  ownerName: '',
                  role: 'owner',
                  memberCount: 1,
                  billCount: 0),
        );
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '我的'),
      body: AuraBackground(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _userCard(),
          const SizedBox(height: 16),
          _ledgerBanner(),
          const SizedBox(height: 20),
          _section('财务'),
          _tile(
            icon: '🧾',
            title: '账单明细',
            subtitle: '查看所有收支记录',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillsScreen()),
            ),
          ),
          _tile(
            icon: '💳',
            title: '账户管理',
            subtitle: '现金、银行卡、支付宝、微信、信用卡…',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
          _tile(
            icon: '🤖',
            title: 'AI 智能导入',
            subtitle: '上传图片 / PDF / Excel / CSV，AI 自动补账单',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiImportsScreen()),
            ),
          ),
          _tile(
            icon: '📋',
            title: '订阅管家',
            subtitle: '周期账单 + AI 自动识别',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          ),
          _tile(
            icon: '📊',
            title: '月报',
            subtitle: '本月 / 上月 AI 总结',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MonthlyReportScreen()),
            ),
          ),
          _tile(
            icon: '📰',
            title: '财经资讯',
            subtitle: '每日全球财经要闻 · AI 中文摘要',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewsScreen()),
            ),
          ),
          _tile(
            icon: '💬',
            title: 'AI 对话助手',
            subtitle: '"这个月外卖花多少？" 这种自然提问',
            onTap: () async {
              final lid = await AuthService.getCurrentLedgerId();
              if (!mounted) return;
              if (lid == null || lid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先选择账本')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(ledgerId: lid)),
              );
            },
          ),
          const SizedBox(height: 20),
          _section('工具'),
          _tile(
            icon: '🧰',
            title: '工具箱',
            subtitle: '贷款 · 个税 · 复利定投 · 汇率换算',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ToolsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          _section('设置'),
          _tile(
            icon: '🎨',
            title: '个性化',
            subtitle: '主题色 · 亮/暗模式',
            onTap: () => _showThemeSheet(),
          ),
          _tile(
            icon: '🔑',
            title: '修改密码',
            subtitle: '换一个登录密码',
            onTap: () => _showChangePasswordSheet(),
          ),
          _tile(
            icon: '⬆️',
            title: '检查更新',
            subtitle: '当前版本 v$kAppVersion',
            onTap: () => UpdateChecker.check(context, manual: true),
          ),
          _tile(
            icon: '🌐',
            title: '关于',
            subtitle: '版本 v$kAppVersion',
            onTap: () => _showAbout(),
          ),
          const SizedBox(height: 20),
          _logoutBtn(),
        ],
        ),
      ),
    );
  }

  Widget _userCard() {
    final fg = AppColors.onPrimaryGradient;
    final hasNick = (_nickname ?? '').trim().isNotEmpty;
    final shown = _displayName;
    return GestureDetector(
      onTap: _editNickname,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.ambientShadow(
            opacity: 0.18,
            blur: 36,
            offset: const Offset(0, 16),
          ),
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                shown.isEmpty ? '?' : shown.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: fg,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      shown,
                      style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_outlined,
                      color: fg.withOpacity(0.8), size: 16),
                ]),
                const SizedBox(height: 4),
                Text(
                  hasNick ? '@$_username' : '点击设置昵称',
                  style: TextStyle(
                      color: fg.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _editNickname() async {
    final ctrl = TextEditingController(text: _nickname ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('修改昵称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '昵称会在共享账本里显示给其他成员。\n清空则使用用户名「$_username」。',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: '请输入昵称',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消'),
          ),
          if ((_nickname ?? '').trim().isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''), // 清除
              child: const Text('清除',
                  style: TextStyle(color: AppColors.expense)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return; // 取消
    try {
      await ApiService.updateProfile(nickname: result);
      if (!mounted) return;
      setState(() {
        _nickname = result.isEmpty ? null : result;
      });
      bumpRefresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.isEmpty ? '已清除昵称' : '昵称已更新'),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('更新失败'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// 当前账本 banner — 显示当前账本 + 一键去管理/切换
  Widget _ledgerBanner() {
    final l = _currentLedger;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LedgersScreen()),
      ).then((_) => _load()),
      child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(l?.displayIcon ?? '💰',
                  style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      l?.name ?? '我的账本',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (l != null && l.isShared)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '共享 ${l.memberCount}人',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  _ledgerCount > 1
                      ? '共 $_ledgerCount 个账本，点击切换或管理'
                      : '点击管理账本 · 可创建多个/邀请家人共享',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.text2),
        ]),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text2)),
      );

  Widget _tile({
    required String icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        radius: 14,
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
                child:
                    Text(icon, style: const TextStyle(fontSize: 20))),
          ),
          title: Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text1)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2)),
          trailing: Icon(Icons.chevron_right_rounded,
              color: AppColors.text2),
        ),
      );

  Widget _logoutBtn() => OutlinedButton.icon(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('退出登录'),
              content: const Text('确定退出当前账号？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定',
                      style: TextStyle(color: AppColors.expense)),
                ),
              ],
            ),
          );
          if (ok == true && mounted) {
            await AuthService.logout();
            // 端到端密钥：清掉本地缓存的私钥 / DEK / 冷却
            await KeyChain.instance.clear();
            PendingDekResolver.resetCooldown();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false);
            }
          }
        },
        icon: const Icon(Icons.logout_rounded, color: AppColors.expense),
        label: const Text('退出登录',
            style: TextStyle(color: AppColors.expense)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      );

  Future<void> _showChangePasswordSheet() async {
    final salt = KeyChain.instance.kdfSaltBase64;
    final priv = KeyChain.instance.sm2PrivKey;
    if (salt == null || priv == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('密钥未就绪，请重新登录'),
      ));
      return;
    }
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool busy = false;
    String? err;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.key_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('修改密码',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码（至少 6 位）',
                  prefixIcon: Icon(Icons.lock_open_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  prefixIcon: Icon(Icons.lock_open_rounded, size: 18),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!,
                    style: TextStyle(color: AppColors.expense, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final oldP = oldCtrl.text;
                        final newP = newCtrl.text;
                        if (oldP.isEmpty || newP.isEmpty) {
                          setLocal(() => err = '请填写完整');
                          return;
                        }
                        if (newP.length < 6) {
                          setLocal(() => err = '新密码至少 6 位');
                          return;
                        }
                        if (newP != confCtrl.text) {
                          setLocal(() => err = '两次输入不一致');
                          return;
                        }
                        if (newP == oldP) {
                          setLocal(() => err = '新密码不能跟旧密码相同');
                          return;
                        }
                        setLocal(() {
                          busy = true;
                          err = null;
                        });
                        try {
                          // 1. 用新密码 + 同 salt 重新加密 privKey（isolate）
                          final newPrivByPwd = await CryptoBootstrap
                              .reencryptPrivByPasswordAsync(
                            privateKeyHex: priv,
                            newPassword: newP,
                            saltBase64: salt,
                          );
                          // 2. POST
                          await ApiService.changePassword(
                            oldPassword: oldP,
                            newPassword: newP,
                            sm2PrivByPwd: newPrivByPwd,
                          );
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                                content: Text('密码已更新，下次登录请用新密码'),
                              ));
                        } catch (e) {
                          setLocal(() {
                            busy = false;
                            err = '失败：${e.toString().replaceAll(RegExp(r'^[^:]*:'), '').trim()}';
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('确认修改'),
              ),
            ],
          ),
        ),
      ),
    );
    oldCtrl.dispose();
    newCtrl.dispose();
    confCtrl.dispose();
  }

  void _showThemeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ThemePickerSheet(),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: '财记',
      applicationVersion: 'v$kAppVersion',
      applicationIcon: const Padding(
        padding: EdgeInsets.all(8),
        child: Text('💰', style: TextStyle(fontSize: 32)),
      ),
      children: const [
        Text('个人财务管理，让每一笔钱都心中有数。'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 主题选择器：底部弹出 — 7 个色块 + 亮/暗模式开关
// ─────────────────────────────────────────────────────────────
class _ThemePickerSheet extends StatefulWidget {
  const _ThemePickerSheet();
  @override
  State<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<_ThemePickerSheet> {
  @override
  Widget build(BuildContext context) {
    final svc = ThemeService.instance;
    return AnimatedBuilder(
      animation: svc.revision,
      builder: (_, __) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(children: [
              Text('个性化',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ]),
            const SizedBox(height: 8),

            // 主题色
            Text('主题色',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: List.generate(
                ThemeService.palettes.length,
                (i) => _ColorTile(
                  palette: ThemeService.palettes[i],
                  selected: svc.paletteIndex == i,
                  onTap: () => svc.setPalette(i),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 亮暗模式
            Text('外观',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(height: 12),
            Row(children: [
              _ModeTile(
                  icon: Icons.light_mode_rounded,
                  label: '浅色',
                  selected: !svc.isDark,
                  onTap: () => svc.setDark(false)),
              const SizedBox(width: 12),
              _ModeTile(
                  icon: Icons.dark_mode_rounded,
                  label: '深色',
                  selected: svc.isDark,
                  onTap: () => svc.setDark(true)),
            ]),
            const SizedBox(height: 16),
            Text(
              '当前：${svc.palette.emoji} ${svc.palette.name} · ${svc.isDark ? "深色" : "浅色"}',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  final ThemePalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ColorTile(
      {required this.palette,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 无色主题的圆显示为"半黑半白"，强调它跟随亮暗模式
    final isMono = palette.isMono;
    final displayColor = isMono ? AppColors.primary : palette.seed;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isMono ? null : palette.seed,
              gradient: isMono
                  ? const LinearGradient(
                      colors: [Color(0xFF101828), Color(0xFFF3F4F6)],
                      stops: [0.5, 0.5],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.text1 : AppColors.border,
                width: selected ? 3 : 1,
              ),
              boxShadow: isMono
                  ? null
                  : [
                      BoxShadow(
                        color: palette.seed.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: selected
                ? Icon(Icons.check_rounded,
                    color: displayColor.computeLuminance() > 0.55
                        ? const Color(0xFF101828)
                        : Colors.white,
                    size: 24)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            palette.name,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.text1 : AppColors.text2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTile(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.text2,
                size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? AppColors.primary : AppColors.text1)),
          ]),
        ),
      ),
    );
  }
}
