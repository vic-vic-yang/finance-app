import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'sm_crypto.dart';

/// 注册 / 登录 / 恢复码 等高层加密流程。
///
/// 与后端 /auth/register 协议一一对应：
///   - 客户端做的事：
///     1. 生成 SM2 keypair
///     2. 生成 16 字节恢复码 + 16 字节 salt
///     3. KDF(密码, salt, 100k) → kekPwd
///        KDF(恢复码, salt, 100k) → kekRecovery
///     4. SM4(kekPwd, privKey) → privByPwd
///        SM4(kekRecovery, privKey) → privByRecovery
///     5. SM3(恢复码 || salt) → recoveryHash
///     6. 生成账本 DEK，用 pubKey 包装 → personalLedgerDekWrapped
///     7. 全部 base64 化上传
class CryptoBootstrap {
  CryptoBootstrap._();

  /// PBKDF2 迭代次数 —— 100k 是手机端能在 ~200ms 内跑完的合理值
  static const _kdfIters = 100000;

  /// 客户端注册前预处理：返回所有要上传的 base64 / hex 字段 + 本地保留的私钥
  static RegisterBundle prepareRegistration({
    required String password,
  }) {
    final swTotal = Stopwatch()..start();

    final sw1 = Stopwatch()..start();
    final kp = SmCrypto.generateKeyPair();
    developer.log('[crypto] SM2 keypair: ${sw1.elapsedMilliseconds}ms');

    final recoveryBytes = SmCrypto.random(16);
    final recoveryCode = _formatRecoveryCode(recoveryBytes);
    final salt = SmCrypto.random(16);

    final sw2 = Stopwatch()..start();
    final kekPwd = SmCrypto.pbkdf2Sm3(password, salt, _kdfIters, 16);
    developer.log('[crypto] PBKDF2 password ($_kdfIters iter): '
        '${sw2.elapsedMilliseconds}ms');

    final sw3 = Stopwatch()..start();
    final kekRec = SmCrypto.pbkdf2Sm3(recoveryCode, salt, _kdfIters, 16);
    developer.log('[crypto] PBKDF2 recovery ($_kdfIters iter): '
        '${sw3.elapsedMilliseconds}ms');

    final privBytes = Uint8List.fromList(utf8.encode(kp.privateKey));
    final privByPwd = SmCrypto.sm4Encrypt(privBytes, kekPwd);
    final privByRec = SmCrypto.sm4Encrypt(privBytes, kekRec);

    final recoveryHash = SmCrypto.sm3(
      Uint8List.fromList([...utf8.encode(recoveryCode), ...salt]),
    );

    final sw4 = Stopwatch()..start();
    final dek = SmCrypto.generateSm4Key();
    final dekWrappedHex = SmCrypto.sm2Encrypt(dek, kp.publicKey);
    final dekWrappedBytes = _hexToBytes(dekWrappedHex);
    developer.log('[crypto] SM2 wrap DEK: ${sw4.elapsedMilliseconds}ms');

    developer.log(
        '[crypto] prepareRegistration TOTAL: ${swTotal.elapsedMilliseconds}ms');

    return RegisterBundle(
      // 发给服务端
      sm2PubKey: kp.publicKey,
      sm2PrivByPwdBase64: base64.encode(privByPwd),
      sm2PrivByRecoveryBase64: base64.encode(privByRec),
      kdfSaltBase64: base64.encode(salt),
      recoveryHashBase64: base64.encode(recoveryHash),
      personalLedgerDekWrappedBase64: base64.encode(dekWrappedBytes),
      // 本地保留
      privateKeyHex: kp.privateKey,
      personalLedgerDek: dek,
      recoveryCode: recoveryCode,
    );
  }

  /// 登录后客户端用密码 + 服务端返回的密钥包，还原私钥
  static String decryptPrivateKeyByPassword({
    required String password,
    required String privByPwdBase64,
    required String saltBase64,
  }) {
    final salt = Uint8List.fromList(base64.decode(saltBase64));
    final kekPwd = SmCrypto.pbkdf2Sm3(password, salt, _kdfIters, 16);
    final blob = Uint8List.fromList(base64.decode(privByPwdBase64));
    final privBytes = SmCrypto.sm4Decrypt(blob, kekPwd);
    return utf8.decode(privBytes);
  }

  /// 忘密码用恢复码还原私钥
  static String decryptPrivateKeyByRecovery({
    required String recoveryCode,
    required String privByRecoveryBase64,
    required String saltBase64,
  }) {
    final salt = Uint8List.fromList(base64.decode(saltBase64));
    final kekRec = SmCrypto.pbkdf2Sm3(
      recoveryCode.trim().toUpperCase(),
      salt,
      _kdfIters,
      16,
    );
    final blob = Uint8List.fromList(base64.decode(privByRecoveryBase64));
    final privBytes = SmCrypto.sm4Decrypt(blob, kekRec);
    return utf8.decode(privBytes);
  }

  /// 用"新密码"重新加密 SM2 私钥 —— 改密码 / 忘密码都用它
  /// 返回 base64 后端可直接存
  static String reencryptPrivByPassword({
    required String privateKeyHex,
    required String newPassword,
    required String saltBase64,
  }) {
    final salt = Uint8List.fromList(base64.decode(saltBase64));
    final kek = SmCrypto.pbkdf2Sm3(newPassword, salt, _kdfIters, 16);
    final privBytes = Uint8List.fromList(utf8.encode(privateKeyHex));
    final blob = SmCrypto.sm4Encrypt(privBytes, kek);
    return base64.encode(blob);
  }

  /// 异步版（PBKDF2 100k 跑 isolate 不阻塞 UI）
  static Future<String> reencryptPrivByPasswordAsync({
    required String privateKeyHex,
    required String newPassword,
    required String saltBase64,
  }) {
    return compute(_isoReencrypt, _ReencryptArgs(
      privateKeyHex: privateKeyHex,
      newPassword: newPassword,
      saltBase64: saltBase64,
    ));
  }

  /// 把 16 字节随机数格式化为 "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX" 这种好抄的样子
  /// 用 32 个 hex char，按 4 个一组分隔
  static String _formatRecoveryCode(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    final raw = sb.toString();
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      groups.add(raw.substring(i, (i + 4).clamp(0, raw.length)));
    }
    return groups.join('-');
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────
  // 异步包装：把重活搬到独立 Isolate（compute），UI 线程不冻结
  // 使用场景：UI 直接 await *Async 方法，spinner 期间页面仍可滑动 / 响应
  // ─────────────────────────────────────────────────────────────

  /// 注册前的密钥生成（PBKDF2 × 2 + SM2 keygen + SM2 wrap）—— 在 isolate 里跑
  static Future<RegisterBundle> prepareRegistrationAsync({
    required String password,
  }) {
    return compute(_isoPrepareRegistration, password);
  }

  /// 登录后用密码解出私钥（PBKDF2 + SM4）—— 在 isolate 里跑
  static Future<String> decryptPrivateKeyByPasswordAsync({
    required String password,
    required String privByPwdBase64,
    required String saltBase64,
  }) {
    return compute(_isoDecryptPrivByPwd, _PwdArgs(
      password: password,
      privByPwdBase64: privByPwdBase64,
      saltBase64: saltBase64,
    ));
  }

  /// 用恢复码解出私钥 —— 在 isolate 里跑
  static Future<String> decryptPrivateKeyByRecoveryAsync({
    required String recoveryCode,
    required String privByRecoveryBase64,
    required String saltBase64,
  }) {
    return compute(_isoDecryptPrivByRec, _RecArgs(
      recoveryCode: recoveryCode,
      privByRecoveryBase64: privByRecoveryBase64,
      saltBase64: saltBase64,
    ));
  }

  /// 批量 SM2 解 DEK —— 在 isolate 里跑
  /// 返回 ledgerId → raw 16-byte DEK 的映射
  static Future<Map<String, Uint8List>> decryptManyDeksAsync({
    required String privateKeyHex,
    required List<DekToUnpack> deks,
  }) {
    return compute(_isoDecryptManyDeks, _DeksArgs(
      privateKeyHex: privateKeyHex,
      deks: deks,
    ));
  }
}

// ── Isolate 入口函数（必须 top-level，compute 才能调用） ──────

RegisterBundle _isoPrepareRegistration(String password) {
  return CryptoBootstrap.prepareRegistration(password: password);
}

String _isoDecryptPrivByPwd(_PwdArgs a) {
  return CryptoBootstrap.decryptPrivateKeyByPassword(
    password: a.password,
    privByPwdBase64: a.privByPwdBase64,
    saltBase64: a.saltBase64,
  );
}

String _isoDecryptPrivByRec(_RecArgs a) {
  return CryptoBootstrap.decryptPrivateKeyByRecovery(
    recoveryCode: a.recoveryCode,
    privByRecoveryBase64: a.privByRecoveryBase64,
    saltBase64: a.saltBase64,
  );
}

String _isoReencrypt(_ReencryptArgs a) {
  return CryptoBootstrap.reencryptPrivByPassword(
    privateKeyHex: a.privateKeyHex,
    newPassword: a.newPassword,
    saltBase64: a.saltBase64,
  );
}

class _ReencryptArgs {
  final String privateKeyHex;
  final String newPassword;
  final String saltBase64;
  const _ReencryptArgs({
    required this.privateKeyHex,
    required this.newPassword,
    required this.saltBase64,
  });
}

Map<String, Uint8List> _isoDecryptManyDeks(_DeksArgs a) {
  final out = <String, Uint8List>{};
  for (final d in a.deks) {
    try {
      final bytes = base64.decode(d.dekWrappedBase64);
      final sb = StringBuffer();
      for (final b in bytes) {
        sb.write(b.toRadixString(16).padLeft(2, '0'));
      }
      out[d.ledgerId] = SmCrypto.sm2Decrypt(sb.toString(), a.privateKeyHex);
    } catch (_) {
      // 某个 DEK 解不开（私钥不匹配？）跳过，不让一个失败拖垮全部
    }
  }
  return out;
}

class _PwdArgs {
  final String password;
  final String privByPwdBase64;
  final String saltBase64;
  const _PwdArgs({
    required this.password,
    required this.privByPwdBase64,
    required this.saltBase64,
  });
}

class _RecArgs {
  final String recoveryCode;
  final String privByRecoveryBase64;
  final String saltBase64;
  const _RecArgs({
    required this.recoveryCode,
    required this.privByRecoveryBase64,
    required this.saltBase64,
  });
}

class _DeksArgs {
  final String privateKeyHex;
  final List<DekToUnpack> deks;
  const _DeksArgs({required this.privateKeyHex, required this.deks});
}

/// 待解的 DEK 输入项（compute 跨 isolate 传值用）
class DekToUnpack {
  final String ledgerId;
  final String dekWrappedBase64;
  final int dekVersion;
  const DekToUnpack({
    required this.ledgerId,
    required this.dekWrappedBase64,
    required this.dekVersion,
  });
}

/// 注册时一次性算出的所有材料
class RegisterBundle {
  // ── 上传到服务端 ──────────────
  final String sm2PubKey;
  final String sm2PrivByPwdBase64;
  final String sm2PrivByRecoveryBase64;
  final String kdfSaltBase64;
  final String recoveryHashBase64;
  final String personalLedgerDekWrappedBase64;

  // ── 本地立刻使用 ──────────────
  final String privateKeyHex;
  final Uint8List personalLedgerDek;

  // ── 必须立刻让用户保存 ────────
  final String recoveryCode;

  RegisterBundle({
    required this.sm2PubKey,
    required this.sm2PrivByPwdBase64,
    required this.sm2PrivByRecoveryBase64,
    required this.kdfSaltBase64,
    required this.recoveryHashBase64,
    required this.personalLedgerDekWrappedBase64,
    required this.privateKeyHex,
    required this.personalLedgerDek,
    required this.recoveryCode,
  });
}
