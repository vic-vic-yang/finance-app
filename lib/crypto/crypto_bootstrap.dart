import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

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
