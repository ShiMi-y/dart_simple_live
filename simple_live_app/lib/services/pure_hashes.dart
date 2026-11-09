import 'dart:typed_data';

/// SHA3（Keccak）与 Blake2b 的纯 Dart 实现（仅用于哔哩哔哩心跳签名）
class PureHashes {
  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;

  // ---------------- SHA3 ----------------

  static final List<int> _rc = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A,
    0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009, 0x000000000000008A,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
    0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
    0x000000000000800A, 0x800000008000000A, 0x8000000080008081,
    0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
  ];

  static final List<int> _rot = [
    1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62,
    18, 39, 61, 20, 44
  ];

  static final List<int> _piln = [
    10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20,
    14, 22, 9, 6, 1
  ];

  static int _rotl(int x, int n) {
    n &= 63;
    if (n == 0) return x;
    return (x << n) | (x >>> (64 - n));
  }

  static void _keccakF(List<int> st) {
    var bc = List<int>.filled(5, 0);
    for (var round = 0; round < 24; round++) {
      for (var i = 0; i < 5; i++) {
        bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
      }
      for (var i = 0; i < 5; i++) {
        var t = bc[(i + 4) % 5] ^ _rotl(bc[(i + 1) % 5], 1);
        for (var j = 0; j < 25; j += 5) {
          st[j + i] ^= t;
        }
      }
      var t = st[1];
      for (var i = 0; i < 24; i++) {
        var j = _piln[i];
        var tmp = st[j];
        st[j] = _rotl(t, _rot[i]);
        t = tmp;
      }
      for (var j = 0; j < 25; j += 5) {
        for (var i = 0; i < 5; i++) {
          bc[i] = st[j + i];
        }
        for (var i = 0; i < 5; i++) {
          st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }
      }
      st[0] ^= _rc[round];
    }
  }

  /// bits: 384 或 512
  static Uint8List sha3(int bits, List<int> data) {
    var rate = (1600 - bits * 2) ~/ 8;
    var st = List<int>.filled(25, 0);
    var msg = List<int>.from(data)..add(0x06);
    while (msg.length % rate != 0) {
      msg.add(0x00);
    }
    msg[msg.length - 1] |= 0x80;
    for (var off = 0; off < msg.length; off += rate) {
      for (var i = 0; i < rate ~/ 8; i++) {
        var v = 0;
        for (var b = 7; b >= 0; b--) {
          v = (v << 8) | msg[off + i * 8 + b];
        }
        st[i] ^= v;
      }
      _keccakF(st);
    }
    var out = Uint8List(bits ~/ 8);
    var idx = 0;
    while (idx < out.length) {
      for (var i = 0; i < rate ~/ 8 && idx < out.length; i++) {
        var v = st[i];
        for (var b = 0; b < 8 && idx < out.length; b++) {
          out[idx++] = (v >>> (8 * b)) & 0xFF;
        }
      }
      if (idx < out.length) _keccakF(st);
    }
    return out;
  }

  // ---------------- Blake2b ----------------

  static final List<int> _blakeIv = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b,
    0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f,
    0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
  ];

  static final List<List<int>> _blakeSigma = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ];

  static int _rotr64(int x, int n) {
    if (n == 0) return x;
    return (x >>> n) | (x << (64 - n));
  }

  static void _blakeCompress(List<int> h, List<int> m, int t0, int t1, bool last) {
    var v = List<int>.filled(16, 0);
    for (var i = 0; i < 8; i++) {
      v[i] = h[i];
      v[i + 8] = _blakeIv[i];
    }
    v[12] ^= t0;
    v[13] ^= t1;
    if (last) v[14] ^= _mask64;

    void g(int a, int b, int c, int d, int x, int y) {
      v[a] = (v[a] + v[b] + x) & _mask64;
      v[d] = _rotr64(v[d] ^ v[a], 32);
      v[c] = (v[c] + v[d]) & _mask64;
      v[b] = _rotr64(v[b] ^ v[c], 24);
      v[a] = (v[a] + v[b] + y) & _mask64;
      v[d] = _rotr64(v[d] ^ v[a], 16);
      v[c] = (v[c] + v[d]) & _mask64;
      v[b] = _rotr64(v[b] ^ v[c], 63);
    }

    for (var r = 0; r < 12; r++) {
      var s = _blakeSigma[r % 10];
      g(0, 4, 8, 12, m[s[0]], m[s[1]]);
      g(1, 5, 9, 13, m[s[2]], m[s[3]]);
      g(2, 6, 10, 14, m[s[4]], m[s[5]]);
      g(3, 7, 11, 15, m[s[6]], m[s[7]]);
      g(0, 5, 10, 15, m[s[8]], m[s[9]]);
      g(1, 6, 11, 12, m[s[10]], m[s[11]]);
      g(2, 7, 8, 13, m[s[12]], m[s[13]]);
      g(3, 4, 9, 14, m[s[14]], m[s[15]]);
    }
    for (var i = 0; i < 8; i++) {
      h[i] ^= v[i] ^ v[i + 8];
    }
  }

  /// Blake2b，输出 digestSize 字节（默认 64）
  static Uint8List blake2b(List<int> data, {int digestSize = 64}) {
    var h = List<int>.from(_blakeIv);
    h[0] ^= 0x01010000 ^ digestSize;

    var blockSize = 128;
    var offset = 0;
    var t = 0;
    while (data.length - offset > blockSize) {
      var m = List<int>.filled(16, 0);
      for (var i = 0; i < 16; i++) {
        var v = 0;
        for (var b = 7; b >= 0; b--) {
          v = (v << 8) | data[offset + i * 8 + b];
        }
        m[i] = v;
      }
      t += blockSize;
      _blakeCompress(h, m, t & _mask64, t >> 32, false);
      offset += blockSize;
    }

    var remaining = data.length - offset;
    var last = List<int>.filled(blockSize, 0);
    for (var i = 0; i < remaining; i++) {
      last[i] = data[offset + i];
    }
    var m = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      var v = 0;
      for (var b = 7; b >= 0; b--) {
        v = (v << 8) | last[i * 8 + b];
      }
      m[i] = v;
    }
    t += remaining;
    _blakeCompress(h, m, t & _mask64, t >> 32, true);

    var out = Uint8List(digestSize);
    for (var i = 0; i < digestSize; i++) {
      out[i] = (h[i ~/ 8] >>> (8 * (i % 8))) & 0xFF;
    }
    return out;
  }
}
