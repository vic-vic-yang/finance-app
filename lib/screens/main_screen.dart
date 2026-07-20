import 'package:flutter/material.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/theme_service.dart';
import '../core/update_checker.dart';
import '../widgets/glass.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import 'bills_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// tab 转场滑动方向：目标 index 更大 → 新内容从右侧（+16px）滑入，反之左侧
  double _slideFrom = 1;

  /// tab 转场控制器：fade 0→1 + 水平 ±16→0，时长 [Motion.base]。
  /// 动画只作用在 IndexedStack 整体外层（Opacity/Transform），不卸载任何
  /// 子页面 —— 4 个 tab 的 State / 滚动位置 / 已加载数据全部保活。
  late final AnimationController _tabCtrl = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1, // 首帧即终态：冷启动不播转场
  );
  late final CurvedAnimation _tabAnim =
      CurvedAnimation(parent: _tabCtrl, curve: Motion.standard);

  @override
  void initState() {
    super.initState();
    // 进入主界面后检查 App 更新（有新版弹提示），静默失败
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context);
    });
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  /// 统一切 tab 入口：决定滑入方向后重播转场。
  /// 系统「减弱动效」时直接落终态（见 Motion.reduced）。
  void _switchTab(int i) {
    if (i == _index) return;
    setState(() {
      _slideFrom = i > _index ? 1 : -1;
      _index = i;
    });
    if (Motion.reduced(context)) {
      _tabCtrl.value = 1;
    } else {
      _tabCtrl.forward(from: 0);
    }
  }

  // tab 顺序：0=主页 1=账单 2=统计 3=我的
  static const _labels      = ['主页', '账单', '统计', '我的'];
  static const _icons       = [
    Icons.home_outlined,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
    Icons.person_outline_rounded,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.receipt_long_rounded,
    Icons.bar_chart_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    // 直接监听主题服务 —— 切换主题时本 widget 强制 rebuild，
    // 所有子页面也跟着重建，AppColors getter 拿到新色。
    // 主题 rebuild 不触碰 _tabCtrl，不会误播 tab 转场。
    return AnimatedBuilder(
      animation: ThemeService.instance.revision,
      builder: (_, __) {
        // 故意不用 const —— 每次 rebuild 创建新的 widget 实例，
        // 让 Flutter 重新走 build() 路径（State 由 AutomaticKeepAliveClientMixin 保活）
        final pages = <Widget>[
          HomeScreen(onSwitchTab: _switchTab),
          const BillsScreen(isTab: true),
          StatsScreen(),
          const ProfileScreen(),
        ];
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: AuraBackground(
            child: Stack(
              children: [
                // tab 转场：只对 IndexedStack 整体做 Opacity/Transform，
                // stack 本身常驻 —— 子页面 State / 滚动位置 / 数据全部保活
                AnimatedBuilder(
                  animation: _tabAnim,
                  child: IndexedStack(index: _index, children: pages),
                  builder: (context, child) {
                    final t = _tabAnim.value;
                    if (t >= 1) return child!;
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(16 * _slideFrom * (1 - t), 0),
                        child: child,
                      ),
                    );
                  },
                ),
                // 底部渐隐：内容滚到底淡出为背景色，避免透过悬浮导航栏周围的空隙看到内容
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 96,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.bg.withValues(alpha: 0),
                            AppColors.bg,
                          ],
                          stops: const [0.0, 0.72],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: GlassNavBar(
            index: _index,
            labels: _labels,
            icons: _icons,
            activeIcons: _activeIcons,
            onTap: _switchTab,
            // 中央「+」记一笔（保存后 AddBillScreen 会 bumpRefresh 通知各页刷新）
            onAdd: () => Navigator.pushNamed(context, '/add'),
          ),
        );
      },
    );
  }
}
