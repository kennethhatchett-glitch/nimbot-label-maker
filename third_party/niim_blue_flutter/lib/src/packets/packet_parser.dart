import 'dart:typed_data';
import 'packet.dart';
import 'commands.dart';

/// Packet parsers
class PacketParser {
  /// Parse raw data containing one or more packets.
  ///
  /// For example, `55554a01044faaaa5555f60101f6aaaa` will be converted to two NiimbotPackets.
  ///
  /// Returns list of packet objects
  static List<NiimbotPacket> parsePacketBundle(Uint8List buf) {
    final chunks = <_PacketChunk>[];
    final bufLength = buf.length;
    int offset = 0;

    while (offset < buf.length) {
      if (!_hasSubarrayAtPos(buf, NiimbotPacket.head, offset)) {
        break;
      }

      if (buf.length - offset < 3) {
        break;
      }

      final cmd = buf[offset + 2];
      bool isCrc32 = false;

      int sizePos = offset + 3;
      int crcSize = 1;

      // Check if this is a CRC32 packet (firmware exchange)
      if (FirmwareExchangePackets.rx.any((e) => e.value == cmd) ||
          FirmwareExchangePackets.tx.any((e) => e.value == cmd)) {
        isCrc32 = true;
        sizePos = offset + 5;
        crcSize = 4;
      }

      if (buf.length <= sizePos) {
        break;
      }

      final size = buf[sizePos];

      if (buf.length <= sizePos + size + crcSize + NiimbotPacket.tail.length) {
        break;
      }

      final tailPos = sizePos + size + crcSize + 1;

      if (!_hasSubarrayAtPos(buf, NiimbotPacket.tail, tailPos)) {
        // Invalid tail found, stop parsing
        break;
      }

      final tailEnd = tailPos + NiimbotPacket.tail.length;

      chunks.add(_PacketChunk(
        isCrc32: isCrc32,
        raw: buf.sublist(offset, tailEnd),
      ));

      offset = tailEnd;
    }

    final chunksDataLen = chunks.fold<int>(0, (acc, c) => acc + c.raw.length);

    if (bufLength != chunksDataLen) {
      throw Exception(
          'Splitted chunks data length not equals buffer length ($bufLength != $chunksDataLen)');
    }

    return chunks.map((c) {
      if (c.isCrc32) {
        return NiimbotCrc32Packet.fromBytesCrc32(c.raw);
      } else {
        return NiimbotPacket.fromBytes(c.raw);
      }
    }).toList();
  }

  /// Check if a subarray exists at a specific position
  static bool _hasSubarrayAtPos(Uint8List buf, Uint8List sub, int pos) {
    if (pos + sub.length > buf.length) return false;
    for (int i = 0; i < sub.length; i++) {
      if (buf[pos + i] != sub[i]) return false;
    }
    return true;
  }
}

/// Internal class for packet chunk tracking
class _PacketChunk {
  final bool isCrc32;
  final Uint8List raw;

  _PacketChunk({required this.isCrc32, required this.raw});
}
