import 'package:flutter/material.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../models/bill.dart';
import '../services/api_service.dart';
import '../widgets/bill_card.dart';
import '../widgets/glass.dart';
import 'add_bill_screen.dart';

/// CFO「归类其他」：只列出落在"其他"分类的账单，点一笔进编辑页改分类。
/// 改完该笔离开"其他"分类，刷新后自动从列表移走。
class RecategorizeOtherScreen extends StatefulWidget {
  const RecategorizeOtherScreen({super.key, required this.categoryIds});

  /// 各"其他"分类的 id（一级下的"其他"二级 + 系统"其他支出/收入"）
  final List<String> categoryIds;

  @override
  State<RecategorizeOtherScreen> createState() =>
      _RecategorizeOtherScreenState();
}

class _RecategorizeOtherScreenState extends State<RecategorizeOtherScreen> {
  bool _loading = true;
  List<Bill> _bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final seen = <String>{};
    final all = <Bill>[];
    for (final cid in widget.categoryIds) {
      try {
        final res = await ApiService.getBills(categoryId: cid, limit: 100);
        for (final b in (res['bills'] as List? ?? [])) {
          final bill = Bill.fromJson(b as Map<String, dynamic>);
          if (seen.add(bill.id)) all.add(bill);
        }
      } catch (_) {/* 单个分类失败不影响其它 */}
    }
    all.sort((a, b) => b.date.compareTo(a.date));
    if (mounted) {
      setState(() {
        _bills = all;
        _loading = false;
      });
    }
  }

  Future<void> _edit(Bill bill) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddBillScreen(bill: bill)),
    );
    if (changed == true) {
      bumpRefresh();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '归类「其他」'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _bills.isEmpty
                ? Center(
                    child: Text('都归好类了 ✅',
                        style: TextStyle(color: AppColors.text2)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: Text('点一笔改分类，改完会从这里移走',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.text2)),
                        ),
                        ..._bills.map((bill) => BillCard(
                              bill: bill,
                              onTap: () => _edit(bill),
                            )),
                      ],
                    ),
                  ),
      ),
    );
  }
}
