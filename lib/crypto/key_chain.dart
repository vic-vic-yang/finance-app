import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sm_crypto.dart';

/// 应用级密钥管理：
///   - 用户 SM2 私钥（端到端，仅本地解开）
///   - 各个账本的 DEK（用户私钥 SM2 解出来后缓存）
///
/// 设计要点：
///   - 内存里持有明文，登出 / 清缓存即丢
///   - 持久化（可选）走 flutter_secure_storage（iOS Keychain / Android Keystore）
///     用于"信任此设备"场景；默认不持久化，重启需重新输密码
class KeyChain {
  KeyChain._();
  static final instance = KeyChain._();

  static const _kPrivKeyStorageKey = 'sm2_priv_key_hex';
  static const _kPubKeyStorageKey = 'sm2_pub_key_hex';
  static const _kKdfSaltStorageKey = 'kdf_salt_b64';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _sm2PubKey;
  String? _sm2PrivKey;
  String? _kdfSaltBase64;

  /// ledgerId → DEK (16 bytes) cache
  final Map<String, Uint8List> _deks = {};

  /// ledgerId → 服务端记录的 DEK 版本
  final Map<String, int> _dekVersions = {};

  String? get sm2PubKey => _sm2PubKey;
  String? get sm2PrivKey => _sm2PrivKey;
  /// PBKDF2 salt（base64）—— 改密码时不再问服务端
  String? get kdfSaltBase64 => _kdfSaltBase64;
  bool get hasKey => _sm2PrivKey != null;

  /// 登录 / 注册成功后调：把刚解出的私钥放进 KeyChain
  Future<void> setSelf({
    required String pubKey,
    required String privKey,
    String? kdfSaltBase64,
    bool persist = true,
  }) async {
    _sm2PubKey = pubKey;
    _sm2PrivKey = privKey;
    if (kdfSaltBase64 != null) _kdfSaltBase64 = kdfSaltBase64;
    if (persist) {
      await _storage.write(key: _kPubKeyStorageKey, value: pubKey);
      await _storage.write(key: _kPrivKeyStorageKey, value: privKey);
      if (kdfSaltBase64 != null) {
        await _storage.write(key: _kKdfSaltStorageKey, value: kdfSaltBase64);
      }
    }
  }

  /// 启动时尝试从 SecureStorage 恢复
  Future<bool> restoreFromStorage() async {
    final pub = await _storage.read(key: _kPubKeyStorageKey);
    final priv = await _storage.read(key: _kPrivKeyStorageKey);
    if (pub == null || priv == null) return false;
    _sm2PubKey = pub;
    _sm2PrivKey = priv;
    _kdfSaltBase64 = await _storage.read(key: _kKdfSaltStorageKey);
    return true;
  }

  /// 登出 / 修改密码 / 切账号：完全清空
  Future<void> clear() async {
    _sm2PubKey = null;
    _sm2PrivKey = null;
    _kdfSaltBase64 = null;
    _deks.clear();
    _dekVersions.clear();
    await _storage.delete(key: _kPubKeyStorageKey);
    await _storage.delete(key: _kPrivKeyStorageKey);
    await _storage.delete(key: _kKdfSaltStorageKey);
  }

  // ── DEK 管理 ───────────────────────────────────────────

  /// 把一个"该账本的 DEK 包装密文（base64）"在本地解开并缓存
  void loadDek({
    required String ledgerId,
    required String dekWrappedBase64,
    required int dekVersion,
  }) {
    final priv = _sm2PrivKey;
    if (priv == null) {
      throw StateError('尚未加载用户私钥，无法解 DEK');
    }
    final wrappedHex = _b64ToHex(dekWrappedBase64);
    final dek = SmCrypto.sm2Decrypt(wrappedHex, priv);
    _deks[ledgerId] = dek;
    _dekVersions[ledgerId] = dekVersion;
  }

  /// 直接装入已解开的 DEK（在 isolate 里批量解完后用，避免 UI 线程再做 SM2）
  void putDek({
    required String ledgerId,
    required Uint8List rawDek,
    required int dekVersion,
  }) {
    _deks[ledgerId] = rawDek;
    _dekVersions[ledgerId] = dekVersion;
  }

  /// 已缓存的 DEK 取出来
  Uint8List? dekOf(String ledgerId) => _deks[ledgerId];
  int? dekVersionOf(String ledgerId) => _dekVersions[ledgerId];

  bool hasDek(String ledgerId) => _deks.containsKey(ledgerId);

  /// 用所有已缓存的 DEK 依次尝试解密（恢复备份时用：事先不知道
  /// 文件属于哪个账本，SM3-HMAC 校验天然能筛出正确的那把）。
  /// 返回匹配的 (ledgerId, 明文)；全部失败返回 null。
  ({String ledgerId, Uint8List plain})? tryDecryptWithAnyDek(Uint8List blob) {
    for (final e in _deks.entries) {
      try {
        return (ledgerId: e.key, plain: SmCrypto.sm4Decrypt(blob, e.value));
      } catch (_) {/* 不是这把钥匙，试下一把 */}
    }
    return null;
  }

  /// 防丢失补救：如果 hasDek=false，调一次 fetcher 拉所有 wrapped DEK
  /// 然后本地解开装入缓存。
  ///
  /// 用法（推荐在所有"加密前置"的 UI 操作处调）：
  ///   if (!await KeyChain.instance.ensureDek(ledgerId, ApiService.getMyDeks)) {
  ///     return _inlineError('账本密钥拉不下来');
  ///   }
  ///
  /// 失败原因常见：
  ///   - 后端/数据库刚启，app 启动那波 getMyDeks 失败被吞了
  ///   - 新加入共享账本还在 pending（DEK 未 wrap 给你）
  Future<bool> ensureDek(
    String ledgerId,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    if (_deks.containsKey(ledgerId)) return true;
    if (_sm2PrivKey == null) return false; // 没私钥就别尝试了
    try {
      final res = await fetcher();
      final list = (res['deks'] as List?) ?? const [];
      for (final d in list) {
        try {
          loadDek(
            ledgerId: (d as Map)['ledgerId'] as String,
            dekWrappedBase64: d['dekWrapped'] as String,
            dekVersion: (d['dekVersion'] as num?)?.toInt() ?? 1,
          );
        } catch (_) {}
      }
    } catch (_) {
      // 网络/服务挂了，不抛
    }
    return _deks.containsKey(ledgerId);
  }

  /// 生成一个新账本的 DEK，并用自己的公钥包装（用于创建账本时）
  /// 返回 (dekRaw, dekWrappedBase64, dekVersion=1)
  ({Uint8List dek, String dekWrappedBase64, int dekVersion}) newDekForOwner() {
    final pub = _sm2PubKey;
    if (pub == null) throw StateError('尚未加载用户公钥');
    final dek = SmCrypto.generateSm4Key();
    final wrappedHex = SmCrypto.sm2Encrypt(dek, pub);
    return (
      dek: dek,
      dekWrappedBase64: _hexToB64(wrappedHex),
      dekVersion: 1
    );
  }

  /// 把一个本地已知的 DEK 用另一人的公钥包装（邀请新成员时）
  String wrapDekFor(Uint8List dek, String targetPubKey) {
    final hex = SmCrypto.sm2Encrypt(dek, targetPubKey);
    return _hexToB64(hex);
  }

  // ── 字段加解密语法糖 ─────────────────────────────────────
  /// 用账本 DEK 加密一段文本，返回 base64 密文
  String encryptText({required String ledgerId, required String plain}) {
    final dek = _deks[ledgerId];
    if (dek == null) {
      throw StateError('账本 $ledgerId 的 DEK 未加载');
    }
    final blob = SmCrypto.sm4Encrypt(
      Uint8List.fromList(utf8.encode(plain)),
      dek,
    );
    return base64.encode(blob);
  }

  /// 用账本 DEK 解密 base64 密文为文本
  /// 如果 dekVer == 0，直接返回"自动入账"占位（服务端写的系统数据）
  String decryptText({
    required String ledgerId,
    required String cipherBase64,
    required int dekVer,
    String systemFallback = '自动入账',
  }) {
    if (dekVer == 0) return systemFallback;
    final dek = _deks[ledgerId];
    if (dek == null) {
      // DEK 还没到位（pending 状态）
      return '【等待解密】';
    }
    try {
      final blob = base64.decode(cipherBase64);
      final plain = SmCrypto.sm4Decrypt(Uint8List.fromList(blob), dek);
      return utf8.decode(plain);
    } catch (e) {
      return '【解密失败】';
    }
  }

  // ── 内部 ───────────────────────────────────────────────
  static String _b64ToHex(String b64) {
    final bytes = base64.decode(b64);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _hexToB64(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return base64.encode(bytes);
  }
}
