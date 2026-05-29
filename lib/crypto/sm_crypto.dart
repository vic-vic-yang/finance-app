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
  /// 用 hashBytesToBytes 直出字节，省一次 bytes→hex→bytes 转换（PBKDF2 热路径关键）
  static Uint8List sm3(Uint8List data) {
    return Uint8List.fromList(SM3.hashBytesToBytes(data));
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
  ///
  /// 优化点（针对 100k 迭代的热路径）：
  ///   - 预先算好 ipad/opad，不要每次 HMAC 内部重复 64 字节 XOR
  ///   - 复用 inner/outer SM3 输入 buffer，只覆写 32 字节 message 部分
  ///   - 用 sm3 直接出字节（已改过，无 hex 转换）
  ///   - 全部用 setRange / 索引写入，避免 _concat 创建临时数组
  ///
  /// 对比未优化版本：100k 迭代 ~减少 30~40% 时间
  static Uint8List pbkdf2Sm3(
    String password,
    Uint8List salt,
    int iterations,
    int dkLen,
  ) {
    const blockSize = 64;
    var pwd = Uint8List.fromList(utf8.encode(password));
    if (pwd.length > blockSize) pwd = sm3(pwd);

    // 预计算 ipad/opad：HMAC 的标准优化
    final ipadKey = Uint8List(blockSize);
    final opadKey = Uint8List(blockSize);
    for (var i = 0; i < pwd.length; i++) {
      ipadKey[i] = 0x36 ^ pwd[i];
      opadKey[i] = 0x5c ^ pwd[i];
    }
    for (var i = pwd.length; i < blockSize; i++) {
      ipadKey[i] = 0x36;
      opadKey[i] = 0x5c;
    }

    final blocks = (dkLen / 32).ceil();
    final out = Uint8List(blocks * 32);

    for (var i = 1; i <= blocks; i++) {
      // 第一次：HMAC(pwd, salt || blockIdx)
      final firstInner = Uint8List(blockSize + salt.length + 4);
      firstInner.setRange(0, blockSize, ipadKey);
      firstInner.setRange(blockSize, blockSize + salt.length, salt);
      firstInner[blockSize + salt.length] = (i >> 24) & 0xff;
      firstInner[blockSize + salt.length + 1] = (i >> 16) & 0xff;
      firstInner[blockSize + salt.length + 2] = (i >> 8) & 0xff;
      firstInner[blockSize + salt.length + 3] = i & 0xff;
      final firstInnerHash = sm3(firstInner);

      final outerBuf = Uint8List(blockSize + 32);
      outerBuf.setRange(0, blockSize, opadKey);
      outerBuf.setRange(blockSize, blockSize + 32, firstInnerHash);
      var u = sm3(outerBuf);

      final t = Uint8List.fromList(u);

      // 后续 iterations - 1 次：HMAC(pwd, u)，u 始终是 32 字节
      // 复用 inner/outer buffer，只改 message 部分
      final innerBuf = Uint8List(blockSize + 32);
      innerBuf.setRange(0, blockSize, ipadKey);

      for (var j = 1; j < iterations; j++) {
        innerBuf.setRange(blockSize, blockSize + 32, u);
        final innerHash = sm3(innerBuf);
        outerBuf.setRange(blockSize, blockSize + 32, innerHash);
        u = sm3(outerBuf);
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
