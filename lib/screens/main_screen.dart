import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/theme_service.dart';
import '../core/update_checker.dart';
import '../widgets/glass.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import 'budgets_screen.dart';
import 'goals_screen.dart';
import 'news_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 进入主界面后检查 App 更新（有新版弹提示），静默失败
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context);
    });
  }

  // tab 顺序：0=主页 1=统计 2=资讯 3=预算 4=目标
  static const _labels      = ['主页', '统计', '资讯', '预算', '目标'];
  static const _icons       = [
    Icons.home_outlined,
    Icons.bar_chart_outlined,
    Icons.newspaper_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.savings_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.newspaper_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.savings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    // 直接监听主题服务 —— 切换主题时本 widget 强制 rebuild，
    // 所有子页面也跟着重建，AppColors getter 拿到新色。
    return AnimatedBuilder(
      animation: ThemeService.instance.revision,
      builder: (_, __) {
        // 故意不用 const —— 每次 rebuild 创建新的 widget 实例，
        // 让 Flutter 重新走 build() 路径（State 由 AutomaticKeepAliveClientMixin 保活）
        final pages = <Widget>[
          HomeScreen(onSwitchTab: (i) => setState(() => _index = i)),
          StatsScreen(),
          const NewsScreen(),
          BudgetsScreen(),
          GoalsScreen(),
        ];
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: AuraBackground(
            child: Stack(
              children: [
                IndexedStack(index: _index, children: pages),
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
                            AppColors.bg.withOpacity(0),
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
            onTap: (i) => setState(() => _index = i),
          ),
        );
      },
    );
  }
}
