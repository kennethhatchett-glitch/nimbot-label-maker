import 'dart:typed_data';
import 'commands.dart';
import '../utils.dart';

/// NIIMBOT packet object
class NiimbotPacket {
  static final Uint8List head = Uint8List.fromList([0x55, 0x55]);
  static final Uint8List tail = Uint8List.fromList([0xAA, 0xAA]);

  final dynamic command; // RequestCommandId or ResponseCommandId
  final Uint8List data;
  List<ResponseCommandId> validResponseIds;
  bool oneWay;

  NiimbotPacket({
    required this.command,
    required Uint8List? data,
    this.validResponseIds = const [],
    this.oneWay = false,
  }) : data = data ?? Uint8List(0);

  /// Data length (header, command, dataLen, checksum, tail are excluded)
  int get dataLength => data.length;

  /// Total packet length including all components
  int get length =>
      head.length + // head
      1 + // cmd
      1 + // dataLength
      dataLength +
      1 + // checksum
      tail.length;

  /// Get command value as int
  int get commandValue {
    if (command is RequestCommandId) {
      return (command as RequestCommandId).value;
    } else if (command is ResponseCommandId) {
      return (command as ResponseCommandId).value;
    } else if (command is int) {
      return command as int;
    }
    throw Exception('Invalid command type');
  }

  /// Calculate XOR checksum
  int get checksum {
    int check = 0;
    check ^= commandValue;
    check ^= data.length;
    for (int i in data) {
      check ^= i;
    }
    return check & 0xFF;
  }

  /// Convert packet to bytes: [0x55, 0x55, CMD, DATA_LEN, DATA, CHECKSUM, 0xAA, 0xAA]
  Uint8List toBytes() {
    final buf = BytesBuilder();

    buf.add(head);
    buf.addByte(commandValue);
    buf.addByte(data.length);
    buf.add(data);
    buf.addByte(checksum);
    buf.add(tail);

    Uint8List result = buf.toBytes();

    // Special case: Connect command needs 0x03 prefix
    if (command == RequestCommandId.connect) {
      final prefixed = BytesBuilder();
      prefixed.addByte(0x03);
      prefixed.add(result);
      return prefixed.toBytes();
    }

    return result;
  }

  /// Parse packet from bytes
  static NiimbotPacket fromBytes(Uint8List buf) {
    const int minPacketSize =
        2 + 1 + 1 + 1 + 2; // head + cmd + len + checksum + tail

    if (buf.length < minPacketSize) {
      throw Exception('Packet is too small (${buf.length} < $minPacketSize)');
    }

    final packetHead = buf.sublist(0, 2);
    final packetTail = buf.sublist(buf.length - 2);

    if (!_u8ArraysEqual(packetHead, head)) {
      throw Exception('Invalid packet head');
    }

    if (!_u8ArraysEqual(packetTail, tail)) {
      throw Exception('Invalid packet tail');
    }

    final int cmd = buf[2];
    final int dataLen = buf[3];

    if (buf.length != minPacketSize + dataLen) {
      throw Exception(
          'Invalid packet size (${buf.length} != ${minPacketSize + dataLen})');
    }

    final data = buf.sublist(4, 4 + dataLen);
    final int receivedChecksum = buf[4 + dataLen];

    // Try ResponseCommandId first, then RequestCommandId (for echo packets)
    dynamic command = ResponseCommandId.fromValue(cmd);
    if (command.value == -1) {
      // Not a valid response command, try request command (echo packet)
      command = RequestCommandId.fromValue(cmd);
    }

    final packet = NiimbotPacket(
      command: command,
      data: data,
    );

    if (packet.checksum != receivedChecksum) {
      throw Exception(
          'Invalid packet checksum (${packet.checksum} != $receivedChecksum)');
    }

    return packet;
  }

  static bool _u8ArraysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'NiimbotPacket(cmd: 0x${commandValue.toRadixString(16)}, dataLen: $dataLength)';
  }
}

/// NIIMBOT packet object with CRC32 checksum. Used in firmware process.
class NiimbotCrc32Packet extends NiimbotPacket {
  final int chunkNumber;

  NiimbotCrc32Packet({
    required super.command,
    required this.chunkNumber,
    required super.data,
    super.validResponseIds = const [],
  });

  /// Calculate CRC32 checksum from command and data
  @override
  int get checksum {
    final builder = BytesBuilder();
    builder.addByte(commandValue);
    builder.add(Utils.u16ToBytes(chunkNumber));
    builder.addByte(data.length);
    builder.add(data);

    final bytes = builder.toBytes();
    return _crc32(bytes);
  }

  /// Convert packet to bytes with CRC32
  @override
  Uint8List toBytes() {
    final buf = BytesBuilder();

    buf.add(NiimbotPacket.head);
    buf.addByte(commandValue);
    buf.add(Utils.u16ToBytes(chunkNumber));
    buf.addByte(data.length);
    buf.add(data);

    // Add CRC32 as 4 bytes (little-endian)
    final crc = checksum;
    buf.addByte((crc) & 0xFF);
    buf.addByte((crc >> 8) & 0xFF);
    buf.addByte((crc >> 16) & 0xFF);
    buf.addByte((crc >> 24) & 0xFF);

    buf.add(NiimbotPacket.tail);

    return buf.toBytes();
  }

  /// Parse CRC32 packet from bytes
  static NiimbotCrc32Packet fromBytesCrc32(Uint8List buf) {
    const int minPacketSize =
        2 + 1 + 2 + 1 + 4 + 2; // head + cmd + chunk + len + crc32 + tail

    if (buf.length < minPacketSize) {
      throw Exception(
          'CRC32 Packet is too small (${buf.length} < $minPacketSize)');
    }

    final packetHead = buf.sublist(0, 2);
    final packetTail = buf.sublist(buf.length - 2);

    if (!NiimbotPacket._u8ArraysEqual(packetHead, NiimbotPacket.head)) {
      throw Exception('Invalid packet head');
    }

    if (!NiimbotPacket._u8ArraysEqual(packetTail, NiimbotPacket.tail)) {
      throw Exception('Invalid packet tail');
    }

    final int cmd = buf[2];
    final int chunkNumber = (buf[3] << 8) | buf[4];
    final int dataLen = buf[5];

    if (buf.length != minPacketSize + dataLen) {
      throw Exception(
          'Invalid CRC32 packet size (${buf.length} != ${minPacketSize + dataLen})');
    }

    final data = buf.sublist(6, 6 + dataLen);

    // Extract CRC32 (4 bytes, little-endian)
    final int receivedCrc = buf[6 + dataLen] |
        (buf[7 + dataLen] << 8) |
        (buf[8 + dataLen] << 16) |
        (buf[9 + dataLen] << 24);

    final packet = NiimbotCrc32Packet(
      command: ResponseCommandId.fromValue(cmd),
      chunkNumber: chunkNumber,
      data: data,
    );

    if (packet.checksum != receivedCrc) {
      throw Exception(
          'Invalid CRC32 checksum (${packet.checksum} != $receivedCrc)');
    }

    return packet;
  }

  /// Calculate CRC32 checksum
  static int _crc32(Uint8List data) {
    // Simple CRC32 implementation
    const int crc32Poly = 0xEDB88320;
    int crc = 0xFFFFFFFF;

    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ crc32Poly;
        } else {
          crc = crc >> 1;
        }
      }
    }

    return ~crc & 0xFFFFFFFF;
  }

  @override
  String toString() {
    return 'NiimbotCrc32Packet(cmd: 0x${commandValue.toRadixString(16)}, chunk: $chunkNumber, dataLen: $dataLength)';
  }
}
