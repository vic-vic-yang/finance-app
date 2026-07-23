import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/backup_codec.dart';
import '../services/temp_file.dart';
import '../services/webdav_service.dart';
import '../widgets/glass.dart';

/// 加密备份 / 恢复 / WebDAV 上传。
///
/// 隐私不变式：导出文件 = SM4(账本 DEK, 明文数据包)，离开本机的只有密文；
/// 恢复时在本机解开 → 用新账本的新 DEK 重加密各 cipher 字段 → 上传，
/// 服务端收到的一切仍是密文。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  // ── 导出 ──
  bool _exporting = false;
  String _exportStatus = '';
  Uint8List? _exportedBytes;
  String? _exportedFileName;
  Map<String, int>? _exportCounts;
  int _exportFailures = 0;

  // ── 恢复 ──
  bool _restoring = false;

  // ── WebDAV ──
  WebDavConfig? _dav;
  bool _davBusy = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadDav();
  }

  Future<void> _loadDav() async {
    final user = await AuthService.getUser();
    _userId = user?['id'] as String?;
    if (_userId != null) {
      final cfg = await WebDavService.instance.load(_userId!);
      if (mounted) setState(() => _dav = cfg);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ═══════════════════════ 导出 ═══════════════════════

  Future<void> _doExport() async {
    setState(() {
      _exporting = true;
      _exportStatus = '准备中…';
      _exportedBytes = null;
      _exportedFileName = null;
      _exportCounts = null;
      _exportFailures = 0;
    });
    try {
      final lid = await AuthService.getCurrentLedgerId();
      if (lid == null || lid.isEmpty) throw Exception('请先选择账本');
      final kc = KeyChain.instance;
      if (!await kc.ensureDek(lid, ApiService.getMyDeks)) {
        throw Exception('账本密钥未就绪，请重新登录后再试');
      }
      final dek = kc.dekOf(lid)!;

      // 账本名
      setState(() => _exportStatus = '读取账本信息…');
      final ledgersRes = await ApiService.getLedgers();
      final ledgers = (ledgersRes['ledgers'] as List? ?? []);
      final mine = ledgers.firstWhere((l) => l['id'] == lid,
          orElse: () => const {'name': '我的账本', 'icon': '📒'});
      final ledgerName = (mine['name'] as String?) ?? '我的账本';
      final ledgerIcon = mine['icon'] as String?;

      // 账单分页全量拉取（服务端 limit 无硬上限，500/页）
      final bills = <dynamic>[];
      var page = 1;
      var totalPages = 1;
      do {
        setState(() => _exportStatus = '拉取账单（第 $page 页）…');
        final res = await ApiService.getBills(page: page, limit: 500);
        bills.addAll((res['bills'] as List? ?? []));
        totalPages =
            ((res['pagination'] as Map?)?['totalPages'] as num?)?.toInt() ??
                1;
        page++;
      } while (page <= totalPages);

      setState(() => _exportStatus = '拉取账户 / 分类 / 预算…');
      final accountsRes = await ApiService.getAccounts();
      final categoriesRes = await ApiService.getCategories();
      final budgetsRes = await ApiService.getBudgets();
      final goalsRes = await ApiService.getGoals();
      final loansRes = await ApiService.getLoans();
      final recurringRes = await ApiService.recurringList();

      setState(() => _exportStatus = '本机解密并打包…');
      final (:bundle, :decryptFailures) = BackupCodec.assembleBundle(
        ledgerName: ledgerName,
        ledgerIcon: ledgerIcon,
        categories: (categoriesRes['categories'] as List? ?? []),
        accounts: (accountsRes['accounts'] as List? ?? []),
        bills: bills,
        budgets: (budgetsRes['budgets'] as List? ?? []),
        goals: (goalsRes['goals'] as List? ?? []),
        loans: loansRes,
        recurring: (recurringRes['recurring'] as List? ?? []),
        dek: dek,
      );

      setState(() => _exportStatus = '用账本密钥加密…');
      final fileJson = BackupCodec.encodeFile(bundle: bundle, dek: dek);
      final bytes =
          Uint8List.fromList(utf8.encode(jsonEncode(fileJson)));

      if (!mounted) return;
      setState(() {
        _exportedBytes = bytes;
        _exportedFileName =
            BackupCodec.fileNameFor(ledgerName, DateTime.now());
        _exportFailures = decryptFailures;
        _exportCounts = {
          '账单': (bundle['bills'] as List).length,
          '账户': (bundle['accounts'] as List).length,
          '分类': (bundle['categories'] as List).length,
          '预算': (bundle['budgets'] as List).length,
          '目标': (bundle['goals'] as List).length,
          '借贷': (bundle['loans'] as List).length,
          '周期': (bundle['recurring'] as List).length,
        };
      });
    } catch (e) {
      _toast('导出失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveToFile() async {
    final bytes = _exportedBytes;
    final name = _exportedFileName;
    if (bytes == null || name == null) return;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存加密备份',
        fileName: name,
        bytes: bytes,
      );
      if (path != null) _toast('已保存：$path');
    } catch (e) {
      _toast('保存失败：${_errText(e)}');
    }
  }

  Future<void> _share() async {
    final bytes = _exportedBytes;
    final name = _exportedFileName;
    if (bytes == null || name == null) return;
    try {
      final path = await writeTempFile(name, bytes);
      await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], subject: '司库加密备份'));
    } catch (e) {
      _toast('分享失败：${_errText(e)}');
    }
  }

  Future<void> _uploadToDav() async {
    final bytes = _exportedBytes;
    final name = _exportedFileName;
    if (bytes == null || name == null) return;
    var cfg = _dav;
    if (cfg == null) {
      await _showDavConfig();
      cfg = _dav;
      if (cfg == null) return; // 用户没保存配置
    }
    setState(() => _davBusy = true);
    try {
      await WebDavService.instance.upload(cfg, name, bytes);
      _toast('已上传到 WebDAV：${cfg.directory}/$name');
    } catch (e) {
      _toast('WebDAV 上传失败：${_errText(e)}');
    } finally {
      if (mounted) setState(() => _davBusy = false);
    }
  }

  // ═══════════════════════ 恢复 ═══════════════════════

  Future<void> _pickAndRestore() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '选择司库备份文件',
        type: FileType.custom,
        allowedExtensions: [BackupCodec.fileExtension],
        withData: true,
      );
      final f = picked?.files.firstOrNull;
      final bytes = f?.bytes;
      if (bytes == null) return; // 用户取消

      final Map<String, dynamic> fileJson;
      try {
        fileJson = (jsonDecode(utf8.decode(bytes)) as Map)
            .cast<String, dynamic>();
      } catch (_) {
        throw Exception('文件不是有效的司库备份（JSON 解析失败）');
      }
      final blob = BackupCodec.payloadBlobOf(fileJson);

      // 把服务端登记的所有 DEK 都拉下来解开（可能是在另一台设备/新装的 App）
      final kc = KeyChain.instance;
      try {
        final res = await ApiService.getMyDeks();
        for (final d in (res['deks'] as List? ?? [])) {
          final m = d as Map;
          final lid = m['ledgerId'] as String;
          if (!kc.hasDek(lid)) {
            try {
              kc.loadDek(
                ledgerId: lid,
                dekWrappedBase64: m['dekWrapped'] as String,
                dekVersion: (m['dekVersion'] as num?)?.toInt() ?? 1,
              );
            } catch (_) {/* 单个 DEK 解不开就跳过 */}
          }
        }
      } catch (_) {/* 网络失败也能继续：本机缓存的 DEK 可能已够 */}

      final hit = kc.tryDecryptWithAnyDek(blob);
      if (hit == null) {
        throw Exception('本机没有能解开此备份的密钥。\n'
            '备份用原账本的密钥加密，请在导出时使用的同一账号下操作；'
            '若该账本已删除，则无法恢复。');
      }
      final bundle = BackupCodec.decodePayload(
          blob, kc.dekOf(hit.ledgerId)!);

      if (!mounted) return;
      await _confirmAndRestore(bundle, fileJson);
    } catch (e) {
      _toast(_errText(e));
    }
  }

  Future<void> _confirmAndRestore(
    Map<String, dynamic> bundle,
    Map<String, dynamic> fileJson,
  ) async {
    final srcName = (bundle['ledgerName'] as String?) ?? '备份账本';
    final exportedAt = (fileJson['exportedAt'] as String?) ?? '';
    final nameCtrl = TextEditingController(text: '$srcName（恢复）');
    final counts = <String, int>{
      '账单': (bundle['bills'] as List?)?.length ?? 0,
      '账户': (bundle['accounts'] as List?)?.length ?? 0,
      '分类': (bundle['categories'] as List?)?.length ?? 0,
      '预算': (bundle['budgets'] as List?)?.length ?? 0,
      '目标': (bundle['goals'] as List?)?.length ?? 0,
      '借贷': (bundle['loans'] as List?)?.length ?? 0,
      '周期': (bundle['recurring'] as List?)?.length ?? 0,
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('恢复备份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('来源账本：$srcName',
                  style: TextStyle(fontSize: 13, color: AppColors.text1)),
              if (exportedAt.isNotEmpty)
                Text('导出时间：$exportedAt',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.text2)),
              const SizedBox(height: 8),
              Text(
                counts.entries
                    .where((e) => e.value > 0)
                    .map((e) => '${e.key} ${e.value}')
                    .join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '恢复为（新账本名）',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '将创建一个新账本（不会覆盖任何现有账本），数据用新密钥重新加密后导入。',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始恢复')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    try {
      final kc = KeyChain.instance;
      final nd = kc.newDekForOwner();
      final body = BackupCodec.buildImportBody(
        bundle: bundle,
        newLedgerName: nameCtrl.text.trim().isEmpty
            ? '$srcName（恢复）'
            : nameCtrl.text.trim(),
        dekWrapped: nd.dekWrappedBase64,
        newDek: nd.dek,
      );
      final res = await ApiService.importBackup(body);
      final newLedger = (res['ledger'] as Map?)?.cast<String, dynamic>();
      final newLedgerId = newLedger?['id'] as String?;
      if (newLedgerId != null) {
        // 新 DEK 装入 KeyChain，恢复出的账本立刻可读
        kc.putDek(
            ledgerId: newLedgerId, rawDek: nd.dek, dekVersion: 1);
      }
      bumpRefresh();
      if (!mounted) return;
      await _showRestoreResult(res, newLedgerId);
    } catch (e) {
      _toast('恢复失败：${_errText(e)}\n（服务端已整体回滚，未产生半成品账本）');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _showRestoreResult(
      Map<String, dynamic> res, String? newLedgerId) async {
    final counts = (res['counts'] as Map?) ?? const {};
    final stats = (res['stats'] as Map?) ?? const {};
    final dropped = (stats['dropped'] as Map?) ?? const {};
    final nulled = (stats['nulled'] as Map?) ?? const {};
    final droppedTotal = (dropped['bills'] as num? ?? 0) +
        (dropped['budgets'] as num? ?? 0) +
        (dropped['recurring'] as num? ?? 0);
    final nulledTotal = (nulled['goalAccounts'] as num? ?? 0) +
        (nulled['loanAccounts'] as num? ?? 0) +
        (nulled['categoryParents'] as num? ?? 0) +
        (nulled['autoDepositCategories'] as num? ?? 0);

    final lines = <String>[
      for (final e in counts.entries)
        if ((e.value as num? ?? 0) > 0 || e.key == 'bills')
          '${_labelOf(e.key)} ${e.value}',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('恢复完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lines.join(' · '),
                style: TextStyle(fontSize: 13, color: AppColors.text1)),
            if (droppedTotal > 0) ...[
              const SizedBox(height: 8),
              Text(
                '有 $droppedTotal 条记录因引用的账户/分类不在备份中而跳过（多为其他成员的私人账户数据）。',
                style: TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ],
            if (nulledTotal > 0) ...[
              const SizedBox(height: 6),
              Text(
                '有 $nulledTotal 处失效的关联已自动解除（如目标绑定的账户已不存在）。',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('完成')),
          if (newLedgerId != null)
            FilledButton(
              onPressed: () async {
                try {
                  await ApiService.switchLedger(newLedgerId);
                  bumpRefresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('已切换到恢复的账本');
                } catch (e) {
                  _toast('切换失败：${_errText(e)}');
                }
              },
              child: const Text('切换到该账本'),
            ),
        ],
      ),
    );
  }

  static String _labelOf(String key) {
    const m = {
      'categories': '分类',
      'accounts': '账户',
      'bills': '账单',
      'budgets': '预算',
      'goals': '目标',
      'loans': '借贷',
      'recurring': '周期',
    };
    return m[key] ?? key;
  }

  // ═══════════════════════ WebDAV 配置 ═══════════════════════

  Future<void> _showDavConfig() async {
    final urlCtrl = TextEditingController(text: _dav?.url ?? '');
    final userCtrl = TextEditingController(text: _dav?.username ?? '');
    final passCtrl = TextEditingController(text: _dav?.password ?? '');
    final dirCtrl =
        TextEditingController(text: _dav?.directory ?? '司库备份');
    bool busy = false;
    String? err;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('WebDAV 设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://dav.jianguoyun.com/dav/',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码 / 应用密码'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dirCtrl,
                  decoration: const InputDecoration(
                    labelText: '远端目录',
                    hintText: '司库备份',
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!,
                      style: TextStyle(
                          color: AppColors.expense, fontSize: 12)),
                ],
                const SizedBox(height: 8),
                Text(
                  '配置只保存在本机安全存储；上传的备份文件全程密文，WebDAV 服务端无法读取内容。',
                  style: TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cfg = WebDavConfig(
                        url: urlCtrl.text.trim(),
                        username: userCtrl.text.trim(),
                        password: passCtrl.text,
                        directory: dirCtrl.text.trim().isEmpty
                            ? '司库备份'
                            : dirCtrl.text.trim(),
                      );
                      setLocal(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await WebDavService.instance.testConnection(cfg);
                        setLocal(() {
                          busy = false;
                          err = null;
                        });
                        _toast('连接成功');
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          err = _errText(e);
                        });
                      }
                    },
              child: const Text('测试连接'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (urlCtrl.text.trim().isEmpty) {
                        setLocal(() => err = '请填写服务器地址');
                        return;
                      }
                      final cfg = WebDavConfig(
                        url: urlCtrl.text.trim(),
                        username: userCtrl.text.trim(),
                        password: passCtrl.text,
                        directory: dirCtrl.text.trim().isEmpty
                            ? '司库备份'
                            : dirCtrl.text.trim(),
                      );
                      final uid = _userId;
                      if (uid != null) {
                        await WebDavService.instance.save(uid, cfg);
                      }
                      if (mounted) setState(() => _dav = cfg);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _toast('WebDAV 配置已保存（仅本机）');
  }

  static String _errText(Object e) =>
      e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '').trim();

  // ═══════════════════════ UI ═══════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '加密备份'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _privacyCard(),
          const SizedBox(height: 14),
          _exportCard(),
          const SizedBox(height: 14),
          _restoreCard(),
          const SizedBox(height: 14),
          _davCard(),
        ],
      ),
    );
  }

  Widget _privacyCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child:
                  const Center(child: Text('🔐', style: TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('端到端加密备份',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(height: 4),
                  Text(
                    '备份文件用你的账本密钥（SM4）加密，分享、上传 WebDAV 的都是密文；'
                    '恢复在新账本上用全新密钥重新加密，服务器永远看不到明文。',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.text2, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _exportCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('📤', '导出当前账本'),
            const SizedBox(height: 6),
            Text(
              '把当前账本的账单 / 账户 / 分类 / 预算 / 目标 / 借贷 / 周期账单打成一个加密文件。',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
            const SizedBox(height: 12),
            if (_exporting) ...[
              Row(children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_exportStatus,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ),
              ]),
            ] else if (_exportedBytes == null)
              _wideBtn(
                icon: Icons.archive_outlined,
                label: '开始导出',
                onTap: _doExport,
              )
            else ...[
              Text(
                '已生成：$_exportedFileName',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1),
              ),
              const SizedBox(height: 4),
              Text(
                _exportCounts!.entries
                    .where((e) => e.value > 0)
                    .map((e) => '${e.key} ${e.value}')
                    .join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              if (_exportFailures > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '⚠️ 有 $_exportFailures 条密文字段解密失败，已按空白导出',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.warning),
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _wideBtn(
                    icon: Icons.save_alt_rounded,
                    label: '保存到文件',
                    onTap: _saveToFile,
                    dense: true,
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _wideBtn(
                      icon: Icons.ios_share_rounded,
                      label: '分享',
                      onTap: _share,
                      dense: true,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: _wideBtn(
                    icon: Icons.cloud_upload_outlined,
                    label: 'WebDAV',
                    onTap: _davBusy ? null : _uploadToDav,
                    dense: true,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _doExport,
                  child: const Text('重新导出'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _restoreCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('📥', '从备份恢复'),
            const SizedBox(height: 6),
            Text(
              '选择 .sikubak 文件，恢复为一个新账本（不会覆盖现有账本）。'
              '需要本机持有导出账本的密钥。',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
            const SizedBox(height: 12),
            _wideBtn(
              icon: Icons.restore_rounded,
              label: _restoring ? '恢复中…' : '选择备份文件',
              onTap: _restoring ? null : _pickAndRestore,
            ),
            if (_restoring) ...[
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('解密 → 重加密 → 导入中，数据量大时请稍候…',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ),
              ]),
            ],
          ],
        ),
      );

  Widget _davCard() => GlassCard(
        radius: 16,
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: _showDavConfig,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Center(
                child: Text('☁️', style: TextStyle(fontSize: 20))),
          ),
          title: Text('WebDAV 设置',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text1)),
          subtitle: Text(
            _dav == null ? '未配置 · 支持坚果云 / Nextcloud 等' : _dav!.url,
            style: TextStyle(fontSize: 12, color: AppColors.text2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing:
              Icon(Icons.chevron_right_rounded, color: AppColors.text2),
        ),
      );

  Widget _cardTitle(String icon, String title) => Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
      ]);

  Widget _wideBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool dense = false,
  }) =>
      ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: dense ? 16 : 18),
        label: Text(label, style: TextStyle(fontSize: dense ? 12 : 14)),
        style: ElevatedButton.styleFrom(
          minimumSize: Size(double.infinity, dense ? 42 : 48),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dense ? 10 : 12)),
        ),
      );
}
