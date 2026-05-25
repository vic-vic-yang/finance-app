import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_sm_new/dart_sm_new.dart';

/// 国密算法工具 —— 跟后端 src/crypto/sm.service.ts 一一对应。
///
/// 关键设计：
/// - SM2 加密 / 解密的"明文"统一用 hex 字符串作为载体（避免 utf8 把任意字节截掉/越界）
/// - SM4 用 CBC + SM3-HMAC 自封 AEAD：密文格式 = iv(16) || ct || mac(32)
/// - SM3-HMAC 与后端 (sm.service.ts) 实现一致
class SmCrypto {
  SmCrypto._();

  static final _rng = Random.secure();

  // ── 随机 ───────────────────────────────────────────────
  static Uint8List random(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  // ── SM2 ────────────────────────────────────────────────
  /// 生成 SM2 密钥对（hex 字符串）
  /// publicKey 为未压缩 04|x|y 共 130 char
  /// privateKey 为 64 hex char
  static SmKeyPair generateKeyPair() {
    final kp = SM2.generateKeyPair();
    return SmKeyPair(publicKey: kp.publicKey, privateKey: kp.privateKey);
  }

  /// SM2 加密任意字节流。先把字节 hex-encode 成 ASCII 字符串再走 SM2.encrypt，
  /// 与后端 sm.service.ts 协议一致。
  /// 返回 hex 字符串密文。
  static String sm2Encrypt(Uint8List plain, String publicKeyHex) {
    final hexAsText = _toHex(plain);
    return SM2.encrypt(hexAsText, publicKeyHex);
  }

  /// SM2 解密，返回原始字节
  static Uint8List sm2Decrypt(String cipherHex, String privateKeyHex) {
    final hexAsText = SM2.decrypt(cipherHex, privateKeyHex);
    return _fromHex(hexAsText);
  }

  // ── SM3 ────────────────────────────────────────────────
  /// SM3 哈希，返回 32 字节
  static Uint8List sm3(Uint8List data) {
    final hex = SM3.hashBytes(data.toList());
    return _fromHex(hex);
  }

  /// SM3 HMAC（与后端 sm3Hmac 完全一致）
  static Uint8List sm3Hmac(Uint8List key, Uint8List msg) {
    const blockSize = 64;
    var k = key;
    if (k.length > blockSize) k = sm3(k);
    if (k.length < blockSize) {
      final padded = Uint8List(blockSize);
      padded.setRange(0, k.length, k);
      k = padded;
    }
    final ipad = Uint8List(blockSize);
    final opad = Uint8List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      ipad[i] = 0x36 ^ k[i];
      opad[i] = 0x5c ^ k[i];
    }
    final inner = sm3(_concat([ipad, msg]));
    return sm3(_concat([opad, inner]));
  }

  /// PBKDF2-SM3：用 SM3 作 PRF 派生密钥
  static Uint8List pbkdf2Sm3(
    String password,
    Uint8List salt,
    int iterations,
    int dkLen,
  ) {
    final pwd = Uint8List.fromList(utf8.encode(password));
    final blocks = (dkLen / 32).ceil();
    final out = Uint8List(blocks * 32);
    for (var i = 1; i <= blocks; i++) {
      final blockIdx = Uint8List(4)
        ..buffer.asByteData().setUint32(0, i, Endian.big);
      var u = sm3Hmac(pwd, _concat([salt, blockIdx]));
      final t = Uint8List.fromList(u);
      for (var j = 1; j < iterations; j++) {
        u = sm3Hmac(pwd, u);
        for (var k = 0; k < 32; k++) {
          t[k] ^= u[k];
        }
      }
      out.setRange((i - 1) * 32, i * 32, t);
    }
    return out.sublist(0, dkLen);
  }

  // ── SM4-CBC + SM3-HMAC（AEAD 风格）─────────────────────
  /// 生成 16 字节 SM4 密钥
  static Uint8List generateSm4Key() => random(16);

  /// SM4 加密：返回 iv(16) || ct || mac(32)
  static Uint8List sm4Encrypt(Uint8List plain, Uint8List key) {
    if (key.length != 16) {
      throw ArgumentError('SM4 key 必须 16 字节');
    }
    final iv = random(16);
    final ct = SM4.encryptBytes(
      plain,
      key: key,
      mode: SM4CryptoMode.CBC,
      iv: _toHex(iv),
    );
    final mac = sm3Hmac(key, _concat([iv, ct]));
    return _concat([iv, ct, mac]);
  }

  /// SM4 解密：输入 iv(16) || ct || mac(32)
  static Uint8List sm4Decrypt(Uint8List blob, Uint8List key) {
    if (key.length != 16) {
      throw ArgumentError('SM4 key 必须 16 字节');
    }
    if (blob.length < 16 + 32) {
      throw ArgumentError('密文长度不合法');
    }
    final iv = blob.sublist(0, 16);
    final ct = blob.sublist(16, blob.length - 32);
    final mac = blob.sublist(blob.length - 32);
    final expected = sm3Hmac(key, _concat([iv, ct]));
    if (!_constantTimeEq(mac, expected)) {
      throw StateError('SM4 完整性校验失败');
    }
    return SM4.decryptBytes(
      Uint8List.fromList(ct),
      key: key,
      mode: SM4CryptoMode.CBC,
      iv: _toHex(iv),
    );
  }

  // ── 辅助 ───────────────────────────────────────────────
  static Uint8List _concat(List<Uint8List> parts) {
    var total = 0;
    for (final p in parts) {
      total += p.length;
    }
    final out = Uint8List(total);
    var i = 0;
    for (final p in parts) {
      out.setRange(i, i + p.length, p);
      i += p.length;
    }
    return out;
  }

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _fromHex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool _constantTimeEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class SmKeyPair {
  final String publicKey;
  final String privateKey;
  const SmKeyPair({required this.publicKey, required this.privateKey});
}
