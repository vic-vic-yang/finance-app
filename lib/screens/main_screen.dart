import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/theme_service.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import 'budgets_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _labels      = ['主页', '统计', '预算', '我的'];
  static const _icons       = [
    Icons.home_outlined,
    Icons.bar_chart_outlined,
    Icons.savings_outlined,
    Icons.person_outline_rounded,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.savings_rounded,
    Icons.person_rounded,
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
          ProfileScreen(),
        ];
        return Scaffold(
          body: IndexedStack(index: _index, children: pages),
          floatingActionButton: FloatingActionButton(
            onPressed: _openAdd,
            child: const Icon(Icons.add, size: 28),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _BottomBar(
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

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.labels,
    required this.icons,
    required this.activeIcons,
    required this.onTap,
  });

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _item(0),
              _item(1),
              const SizedBox(width: 72), // FAB space
              _item(2),
              _item(3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final selected = index == i;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcons[i] : icons[i],
              size: 22,
              color: selected ? AppColors.primary : AppColors.text2,
            ),
            const SizedBox(height: 3),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppColors.primary : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
