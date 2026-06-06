import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../../services/api_service.dart';
import 'tools_common.dart';

/// 汇率换算：后端代理最新汇率，本地即时换算。
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _Currency {
  final String code;
  final String flag;
  final String name;
  const _Currency(this.code, this.flag, this.name);
}

const List<_Currency> _currencies = [
  _Currency('CNY', '🇨🇳', '人民币'),
  _Currency('USD', '🇺🇸', '美元'),
  _Currency('EUR', '🇪🇺', '欧元'),
  _Currency('JPY', '🇯🇵', '日元'),
  _Currency('HKD', '🇭🇰', '港币'),
  _Currency('GBP', '🇬🇧', '英镑'),
  _Currency('KRW', '🇰🇷', '韩元'),
  _Currency('AUD', '🇦🇺', '澳元'),
  _Currency('CAD', '🇨🇦', '加元'),
  _Currency('SGD', '🇸🇬', '新加坡元'),
  _Currency('THB', '🇹🇭', '泰铢'),
  _Currency('TWD', '🇨🇳', '新台币'),
  _Currency('MYR', '🇲🇾', '马来西亚林吉特'),
  _Currency('MOP', '🇲🇴', '澳门元'),
  _Currency('CHF', '🇨🇭', '瑞士法郎'),
  _Currency('NZD', '🇳🇿', '新西兰元'),
  _Currency('RUB', '🇷🇺', '卢布'),
  _Currency('INR', '🇮🇳', '印度卢比'),
];

_Currency _cur(String code) =>
    _currencies.firstWhere((c) => c.code == code,
        orElse: () => _Currency(code, '🏳️', code));

class _ExchangeScreenState extends State<ExchangeScreen> {
  final _amountCtrl = TextEditingController(text: '100');
  String _from = 'CNY';
  String _to = 'USD';

  Map<String, double> _rates = {}; // 以 _from 为基准
  String? _updatedAt;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getExchangeRates(base: _from);
      final rawRates = (res['rates'] as Map?) ?? {};
      final rates = <String, double>{};
      rawRates.forEach((k, v) {
        final d = (v is num) ? v.toDouble() : double.tryParse('$v');
        if (d != null) rates[k as String] = d;
      });
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _updatedAt = res['updatedAt'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '获取汇率失败，请检查网络后重试';
        _loading = false;
      });
    }
  }

  double get _amount => toolParse(_amountCtrl.text);
  double? get _rate => _rates[_to];
  double? get _converted => _rate == null ? null : _amount * _rate!;

  void _swap() {
    setState(() {
      final t = _from;
      _from = _to;
      _to = t;
    });
    _load();
  }

  String _fmtUpdated() {
    if (_updatedAt == null) return '';
    try {
      final dt = DateTime.parse(_updatedAt!).toLocal();
      return DateFormat('M月d日 HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '汇率换算',
        actions: [
          IconButton(
            tooltip: '刷新汇率',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            GlassCard(
              radius: 18,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                children: [
                  _currencyRow(
                    label: '从',
                    code: _from,
                    onPick: (c) {
                      setState(() => _from = c);
                      _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  ToolNumField(
                    controller: _amountCtrl,
                    label: '金额',
                    suffix: _from,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: _swap,
                      icon: Icon(Icons.swap_vert_rounded,
                          color: AppColors.primary),
                      tooltip: '互换',
                    ),
                  ),
                  _currencyRow(
                    label: '到',
                    code: _to,
                    onPick: (c) => setState(() => _to = c),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              GlassCard(
                radius: 16,
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded,
                      color: AppColors.expense, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.text2)),
                  ),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ]),
              )
            else
              _resultCard(),
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final converted = _converted;
    return ToolResultCard(
      title: '换算结果',
      children: [
        if (_loading && _rates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text('正在获取最新汇率…',
                  style: TextStyle(fontSize: 13, color: AppColors.text2)),
            ]),
          )
        else ...[
          ToolResultRow(
            label: '${_cur(_to).flag} ${_amount == _amount.truncateToDouble() ? _amount.toInt() : _amount} $_from =',
            value: converted == null
                ? '—'
                : '${toolMoney(converted)} $_to',
            emphasize: true,
          ),
          const Divider(height: 18),
          if (_rate != null)
            ToolResultRow(
              label: '汇率',
              value: '1 $_from = ${_rate!.toStringAsFixed(4)} $_to',
            ),
          if (_rate != null && _rate! > 0)
            ToolResultRow(
              label: '反向',
              value: '1 $_to = ${(1 / _rate!).toStringAsFixed(4)} $_from',
            ),
          if (_updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('数据更新：${_fmtUpdated()}',
                  style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
            ),
        ],
      ],
    );
  }

  Widget _currencyRow({
    required String label,
    required String code,
    required ValueChanged<String> onPick,
  }) {
    final c = _cur(code);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: AppColors.text2)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: InkWell(
            onTap: () => _pickCurrency(onPick),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Text(c.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Text(c.code,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      style:
                          TextStyle(fontSize: 13, color: AppColors.text2),
                      overflow: TextOverflow.ellipsis),
                ),
                Icon(Icons.unfold_more_rounded,
                    size: 18, color: AppColors.text3),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCurrency(ValueChanged<String> onPick) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Text('选择币种',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: AppColors.text2),
                  ),
                ]),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _currencies.length,
                  itemBuilder: (_, i) {
                    final c = _currencies[i];
                    return ListTile(
                      onTap: () => Navigator.pop(context, c.code),
                      leading:
                          Text(c.flag, style: const TextStyle(fontSize: 26)),
                      title: Text('${c.code} · ${c.name}',
                          style: TextStyle(
                              fontSize: 15, color: AppColors.text1)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }
}
