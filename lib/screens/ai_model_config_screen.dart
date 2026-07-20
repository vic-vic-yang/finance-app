import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/llm_config_service.dart';
import '../widgets/siku_ui.dart';
import 'ai_model_edit_screen.dart';

/// AI 模型配置（BYOK）：
/// - 可保存多套厂商配置，点选一套为「使用中」，Key 只存本机（服务端过手不落库）
/// - 打开「共享给账本成员」则把使用中的配置加密上传，账本所有成员共用
class AiModelConfigScreen extends StatefulWidget {
  const AiModelConfigScreen({super.key});

  @override
  State<AiModelConfigScreen> createState() => _AiModelConfigScreenState();
}

class _AiModelConfigScreenState extends State<AiModelConfigScreen> {
  bool _loading = true;
  bool _shareBusy = false;

  List<PersonalLlmConfig> _configs = [];
  String? _activeId;

  // 账本共享现状（他人配置时展示）
  Map<String, dynamic>? _sharedInfo;
  bool _serverDefaultAllowed = false; // 是否 VIP（可用服务端默认模型）

  bool get _sharing => _sharedInfo != null &&
      (_sharedInfo!['isOwner'] as bool? ?? false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LlmConfigService.instance.load();
    _configs = LlmConfigService.instance.configs;
    _activeId = LlmConfigService.instance.active?.id;
    try {
      final res = await ApiService.getLlmConfig();
      _sharedInfo = res['shared'] as Map<String, dynamic>?;
      _serverDefaultAllowed = res['serverDefaultAllowed'] as bool? ?? false;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  PersonalLlmConfig? get _active {
    for (final c in _configs) {
      if (c.id == _activeId) return c;
    }
    return null;
  }

  /// 把「使用中的」配置推为账本共享（共享开启期间切换/增删配置后保持同步）
  Future<void> _pushShare(PersonalLlmConfig cfg) async {
    await ApiService.putLlmConfig(
      provider: cfg.provider,
      baseUrl: cfg.baseUrl,
      modelId: cfg.model,
      visionModelId: cfg.visionModel.isEmpty ? null : cfg.visionModel,
      apiKey: cfg.apiKey,
    );
  }

  Future<void> _switchActive(PersonalLlmConfig cfg) async {
    if (cfg.id == _activeId) return;
    await LlmConfigService.instance.setActive(cfg.id);
    setState(() => _activeId = cfg.id);
    if (_sharing) {
      try {
        await _pushShare(cfg);
        await _load();
        _toast('共享配置已同步为「${cfg.displayName}」');
      } catch (e) {
        _toast('共享同步失败：$e');
      }
    }
  }

  Future<void> _addOrEdit([PersonalLlmConfig? existing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AiModelEditScreen(existing: existing)),
    );
    if (changed == true) {
      await _load();
      // 编辑了使用中的配置且共享开启 → 同步到服务器
      if (_sharing && _active != null) {
        try {
          await _pushShare(_active!);
        } catch (_) {}
      }
    }
  }

  Future<void> _remove(PersonalLlmConfig cfg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这套配置？'),
        content: Text('「${cfg.displayName} · ${cfg.model}」将从本机移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await LlmConfigService.instance.remove(cfg.id);
    await _load();
    // 共享开启时：还有配置则同步新的使用中配置；没有了则关闭服务器共享
    if (_sharing) {
      try {
        if (_active != null) {
          await _pushShare(_active!);
        } else {
          await ApiService.deleteLlmConfig();
        }
        await _load();
      } catch (_) {}
    }
  }

  Future<void> _toggleShare(bool v) async {
    setState(() => _shareBusy = true);
    try {
      if (v) {
        final cfg = _active;
        if (cfg == null) {
          _toast('请先添加并选中一套模型配置');
          return;
        }
        await _pushShare(cfg);
        _toast('已共享给账本成员');
      } else {
        await ApiService.deleteLlmConfig();
        _toast('已关闭共享并删除服务器上的 Key');
      }
      await _load();
    } catch (e) {
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: 'AI 模型',
        actions: [
          HeaderAddButton(
            tooltip: '添加新模型',
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (_sharedInfo != null &&
                      !(_sharedInfo!['isOwner'] as bool? ?? false))
                    _sharedByOthersBanner(),
                  _modelListCard(),
                  const SizedBox(height: 14),
                  _shareCard(),
                  const SizedBox(height: 18),
                  _privacyNote(),
                ],
              ),
      ),
    );
  }

  Widget _sharedByOthersBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.diversity_3_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前账本已由 @${_sharedInfo!['ownerName']} 提供共享模型'
              '（${_sharedInfo!['modelId']}），你无需配置即可使用 AI；'
              '也可以添加自己的进行覆盖。',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.text2, height: 1.5),
            ),
          ),
        ]),
      );

  Widget _modelListCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(
                  child: Text('我的模型',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                ),
                Text('点选切换使用中',
                    style: TextStyle(fontSize: 11, color: AppColors.text3)),
              ]),
            ),
            const SizedBox(height: 6),
            if (_configs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
                child: Text('还没有配置，点右上 + 添加新模型',
                    style: TextStyle(fontSize: 12.5, color: AppColors.text3)),
              )
            else
              for (final c in _configs) _configTile(c),
          ],
        ),
      );

  Widget _configTile(PersonalLlmConfig c) {
    final isActive = c.id == _activeId;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 4, right: 0),
      onTap: () => _switchActive(c),
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: isActive ? AppColors.primary : AppColors.text3,
      ),
      title: Row(children: [
        Flexible(
          child: Text(c.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
        ),
        if (isActive) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('使用中',
                style: TextStyle(fontSize: 10, color: AppColors.primary)),
          ),
        ],
      ]),
      subtitle: Text(
        c.visionModel.isEmpty ? c.model : '${c.model} ｜ 视觉 ${c.visionModel}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: AppColors.text3),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.text2),
          onPressed: () => _addOrEdit(c),
          tooltip: '编辑',
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
          onPressed: () => _remove(c),
          tooltip: '删除',
        ),
      ]),
    );
  }

  Widget _shareCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('共享给账本成员',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          subtitle: Text(
            _sharing
                ? '使用中的配置已加密上传到服务器，本账本所有成员的 AI 功能共用；切换使用中会同步更新'
                : 'Key 仅保存在本机，只有你自己能用',
            style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.4),
          ),
          value: _sharing,
          onChanged: _shareBusy ? null : _toggleShare,
        ),
      );

  Widget _privacyNote() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '隐私说明\n'
            '· 仅本机模式：Key 存手机安全存储，随请求转发给服务器直连模型，服务器不存储。\n'
            '· 共享模式：Key 用服务端密钥 AES-256-GCM 加密后落库，供账本成员共用；'
            '关闭共享即从服务器删除。\n'
            '${_serverDefaultAllowed ? '· 你是 VIP：不配置也可使用服务端内置模型。' : '· 未配置时 AI 功能不可用（记账等核心功能不受影响）。'}',
            style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.7),
          ),
          const SizedBox(height: 12),
          _vipStatusBanner(),
        ],
      );

  Widget _vipStatusBanner() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getVipStatus().catchError((_) => <String, dynamic>{'isVip': false}),
      builder: (_, snap) {
        final data = snap.data;
        if (data == null || data['isVip'] != true) {
          return const SizedBox.shrink();
        }
        final tier = data['vipTier'] as String? ?? '';
        final days = data['remainingDays'] as int? ?? 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Text('👑', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VIP 会员 · $tier',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  if (days > 0)
                    Text('剩余 $days 天',
                        style:
                            TextStyle(fontSize: 11.5, color: AppColors.text2)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('VIP',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onPrimary)),
            ),
          ]),
        );
      },
    );
  }
}
