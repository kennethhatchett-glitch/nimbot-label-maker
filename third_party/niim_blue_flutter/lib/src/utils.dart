import 'dart:typed_data';

/// Utility functions for packet processing
class Utils {
  /// Convert uint16 to bytes (big-endian)
  static Uint8List u16ToBytes(int value) {
    return Uint8List.fromList([
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Convert uint32 to bytes (big-endian)
  static Uint8List u32ToBytes(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Convert bytes to uint16 (big-endian)
  static int bytesToU16(Uint8List bytes, [int offset = 0]) {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  /// Convert bytes to int16 (big-endian, signed)
  static int bytesToI16(Uint8List bytes, [int offset = 0]) {
    final value = (bytes[offset] << 8) | bytes[offset + 1];
    // Convert to signed int16
    return value > 0x7FFF ? value - 0x10000 : value;
  }

  /// Convert bytes to uint32 (big-endian)
  static int bytesToU32(Uint8List bytes, [int offset = 0]) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Convert bytes to hex string
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Convert hex string to bytes
  static Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').replaceAll(':', '');
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  /// Check if two Uint8Lists are equal
  static bool u8ArraysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Validate if two Uint8Lists are equal, throw exception if not
  static void validateU8ArraysEqual(Uint8List a, Uint8List b, String message) {
    if (!u8ArraysEqual(a, b)) {
      throw Exception(message);
    }
  }

  /// Convert ASCII string to bytes
  static Uint8List stringToBytes(String str) {
    return Uint8List.fromList(str.codeUnits);
  }

  /// Convert bytes to ASCII string
  static String bytesToString(Uint8List bytes) {
    return String.fromCharCodes(bytes);
  }

  /// Clamp value between min and max
  static num clamp(num value, num min, num max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Delay for specified milliseconds
  static Future<void> delay(int milliseconds) {
    return Future.delayed(Duration(milliseconds: milliseconds));
  }

  /// Generate random bytes
  static Uint8List randomBytes(int length) {
    final random = DateTime.now().millisecondsSinceEpoch;
    final result = <int>[];
    for (int i = 0; i < length; i++) {
      result.add((random + i) % 256);
    }
    return Uint8List.fromList(result);
  }

  /// Calculate CRC32 checksum
  static int crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;

    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }

    return ~crc & 0xFFFFFFFF;
  }
}

/// Validators
class Validators {
  static void u8ArraysEqual(Uint8List a, Uint8List b, String message) {
    Utils.validateU8ArraysEqual(a, b, message);
  }

  static void isTrue(bool condition, String message) {
    if (!condition) {
      throw Exception(message);
    }
  }

  static void isNotNull(dynamic value, String message) {
    if (value == null) {
      throw Exception(message);
    }
  }

  static void inRange(num value, num min, num max, String message) {
    if (value < min || value > max) {
      throw Exception(message);
    }
  }
}
