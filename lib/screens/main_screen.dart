import 'package:flutter/material.dart';
import '../core/theme_service.dart';
import '../widgets/glass.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import 'budgets_screen.dart';
import 'goals_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _labels      = ['主页', '统计', '预算', '目标'];
  static const _icons       = [
    Icons.home_outlined,
    Icons.bar_chart_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.savings_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.savings_rounded,
  ];

  Future<void> _openAdd() async {
    final result = await Navigator.pushNamed(context, '/add');
    if (result == true) setState(() {}); // trigger child refresh via key
  }

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
          HomeScreen(),
          StatsScreen(),
          BudgetsScreen(),
          GoalsScreen(),
        ];
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: AuraBackground(
            child: IndexedStack(index: _index, children: pages),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _openAdd,
            child: const Icon(Icons.add, size: 28),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
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
