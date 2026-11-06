import 'dart:typed_data';
import '../utils.dart';

/// Utility class to sequentially fetch data from byte array with EOF checks
class SequentialDataReader {
  final Uint8List bytes;
  int _offset = 0;

  SequentialDataReader(this.bytes);

  /// Check if count bytes are available
  bool canRead(int count) {
    return _offset + count <= bytes.length;
  }

  /// Check available bytes and throw exception if EOF met
  void _willRead(int count) {
    if (!canRead(count)) {
      throw Exception('Tried to read too much data');
    }
  }

  /// Skip bytes
  void skip(int len) {
    _willRead(len);
    _offset += len;
  }

  /// Read fixed length bytes
  Uint8List readBytes(int len) {
    _willRead(len);
    final part = bytes.sublist(_offset, _offset + len);
    _offset += len;
    return part;
  }

  /// Read variable length bytes
  Uint8List readVBytes() {
    final len = readI8();
    return readBytes(len);
  }

  /// Read variable length string
  String readVString() {
    final part = readVBytes();
    return Utils.bytesToString(part);
  }

  /// Read 8 bit int (big endian)
  int readI8() {
    _willRead(1);
    final result = bytes[_offset];
    _offset += 1;
    return result;
  }

  /// Read boolean
  bool readBool() {
    return readI8() > 0;
  }

  /// Read 16 bit int (big endian)
  int readI16() {
    _willRead(2);
    final part = bytes.sublist(_offset, _offset + 2);
    _offset += 2;
    return Utils.bytesToU16(part);
  }

  /// Check EOF condition
  void end() {
    if (_offset != bytes.length) {
      throw Exception('Extra data left');
    }
  }

  /// Get current offset
  int get offset => _offset;
}
