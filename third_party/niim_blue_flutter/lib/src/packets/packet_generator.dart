import 'dart:typed_data';
import 'commands.dart';
import 'packet.dart';
import '../utils.dart';
import 'payloads.dart';

/// Options for image packet generation
class ImagePacketsGenerateOptions {
  /// Mode for "black pixel count" section of bitmap packet
  final String countsMode; // 'auto', 'split', or 'total'

  /// Disable PrintBitmapRowIndexed packet
  final bool noIndexPacket;

  /// Send PrinterCheckLine every 200 lines
  final bool enableCheckLine;

  /// Printer head resolution (used for black pixel count calculation)
  final int printheadPixels;

  const ImagePacketsGenerateOptions({
    this.countsMode = 'auto',
    this.noIndexPacket = false,
    this.enableCheckLine = false,
    this.printheadPixels = 0,
  });
}

/// Helper class that generates various types of packets
class PacketGenerator {
  /// Maps a request command ID to its corresponding response IDs and creates a packet object
  static NiimbotPacket mapped(RequestCommandId sendCmd, [List<int>? data]) {
    final dataBytes =
        data != null ? Uint8List.fromList(data) : Uint8List.fromList([1]);
    final respIds = commandsMap[sendCmd];

    if (respIds == null) {
      final p = NiimbotPacket(command: sendCmd, data: dataBytes);
      p.oneWay = true;
      return p;
    }

    return NiimbotPacket(
      command: sendCmd,
      data: dataBytes,
      validResponseIds: respIds,
    );
  }

  static NiimbotPacket connect() => mapped(RequestCommandId.connect);

  static NiimbotPacket getPrinterStatusData() =>
      mapped(RequestCommandId.printerStatusData);

  static NiimbotPacket rfidInfo() => mapped(RequestCommandId.rfidInfo);

  static NiimbotPacket rfidInfo2() => mapped(RequestCommandId.rfidInfo2);

  static NiimbotPacket antiFake(int queryType) =>
      mapped(RequestCommandId.antiFake, [queryType]);

  static NiimbotPacket setAutoShutDownTime(AutoShutdownTime time) =>
      mapped(RequestCommandId.setAutoShutdownTime, [time.value]);

  static NiimbotPacket getPrinterInfo(int type) =>
      mapped(RequestCommandId.printerInfo, [type]);

  static NiimbotPacket setSoundSettings(int soundType, bool on) =>
      mapped(RequestCommandId.soundSettings, [1, soundType, on ? 1 : 0]);

  static NiimbotPacket getSoundSettings(int soundType) =>
      mapped(RequestCommandId.soundSettings, [2, soundType, 1]);

  static NiimbotPacket heartbeat(int type) =>
      mapped(RequestCommandId.heartbeat, [type]);

  static NiimbotPacket setDensity(int value) =>
      mapped(RequestCommandId.setDensity, [value]);

  static NiimbotPacket setLabelType(int value) =>
      mapped(RequestCommandId.setLabelType, [value]);

  static NiimbotPacket setPageSize2b(int rows) =>
      mapped(RequestCommandId.setPageSize, Utils.u16ToBytes(rows).toList());

  /// Set page size with width and height
  /// B1: use setPageSize6b instead to avoid blank pages
  /// D110: works normally
  static NiimbotPacket setPageSize4b(int rows, int cols) => mapped(
      RequestCommandId.setPageSize,
      [...Utils.u16ToBytes(rows), ...Utils.u16ToBytes(cols)]);

  /// Set page size with dimensions and copies count
  static NiimbotPacket setPageSize6b(int rows, int cols, int copiesCount) =>
      mapped(RequestCommandId.setPageSize, [
        ...Utils.u16ToBytes(rows),
        ...Utils.u16ToBytes(cols),
        ...Utils.u16ToBytes(copiesCount)
      ]);

  /// Set page size (13-byte version, first seen on D110M v4)
  static NiimbotPacket setPageSize13b(
    int rows,
    int cols,
    int copiesCount, {
    int cutHeight = 0,
    int cutType = 0,
    int sendAll = 0,
    int partHeight = 0,
  }) =>
      mapped(RequestCommandId.setPageSize, [
        ...Utils.u16ToBytes(rows),
        ...Utils.u16ToBytes(cols),
        ...Utils.u16ToBytes(copiesCount),
        ...Utils.u16ToBytes(cutHeight),
        cutType,
        0x00,
        sendAll,
        ...Utils.u16ToBytes(partHeight),
      ]);

  static NiimbotPacket setPrintQuantity(int quantity) => mapped(
      RequestCommandId.printQuantity, Utils.u16ToBytes(quantity).toList());

  static NiimbotPacket printStatus() => mapped(RequestCommandId.printStatus);

  /// Reset printer settings (sound and maybe some other settings)
  static NiimbotPacket printerReset() => mapped(RequestCommandId.printerReset);

  /// Print start (1-byte version)
  static NiimbotPacket printStart1b() => mapped(RequestCommandId.printStart);

  /// Print start (2-byte version)
  static NiimbotPacket printStart2b(int totalPages) => mapped(
      RequestCommandId.printStart, Utils.u16ToBytes(totalPages).toList());

  /// Print start (7-byte version)
  static NiimbotPacket printStart7b(int totalPages, [int pageColor = 0]) =>
      mapped(RequestCommandId.printStart,
          [...Utils.u16ToBytes(totalPages), 0x00, 0x00, 0x00, 0x00, pageColor]);

  /// Print start (9-byte version, first seen on D110M v4)
  static NiimbotPacket printStart9b(
    int totalPages, {
    int pageColor = 0,
    int quality = 0,
    bool someFlag = false,
  }) =>
      mapped(RequestCommandId.printStart, [
        ...Utils.u16ToBytes(totalPages),
        0x00,
        0x00,
        0x00,
        0x00,
        pageColor,
        quality,
        someFlag ? 0x01 : 0x00
      ]);

  static NiimbotPacket printEnd() => mapped(RequestCommandId.printEnd);

  static NiimbotPacket pageStart() => mapped(RequestCommandId.pageStart);

  static NiimbotPacket pageEnd() => mapped(RequestCommandId.pageEnd);

  static NiimbotPacket printEmptySpace(int pos, int repeats) => mapped(
      RequestCommandId.printEmptyRow, [...Utils.u16ToBytes(pos), repeats]);

  static NiimbotPacket printBitmapRow(
    int pos,
    int repeats,
    Uint8List data,
    int printheadPixels, {
    String countsMode = 'auto',
  }) {
    final counts =
        _countPixelsForBitmapPacket(data, printheadPixels, countsMode);
    return mapped(RequestCommandId.printBitmapRow,
        [...Utils.u16ToBytes(pos), ...counts, repeats, ...data]);
  }

  /// Printer powers off if black pixel count > 6
  static NiimbotPacket printBitmapRowIndexed(
    int pos,
    int repeats,
    Uint8List data,
    int printheadPixels, {
    String countsMode = 'auto',
  }) {
    final counts =
        _countPixelsForBitmapPacket(data, printheadPixels, countsMode);
    final indexes = _indexPixels(data);
    final totalBlackPixels = _countBlackPixels(data);

    if (totalBlackPixels > 6) {
      throw Exception('Black pixel count > 6 ($totalBlackPixels)');
    }

    return mapped(RequestCommandId.printBitmapRowIndexed,
        [...Utils.u16ToBytes(pos), ...counts, repeats, ...indexes]);
  }

  static NiimbotPacket printClear() => mapped(RequestCommandId.printClear);

  static NiimbotPacket writeRfid(Uint8List data) =>
      mapped(RequestCommandId.writeRFID, data.toList());

  static NiimbotPacket checkLine(int line) => mapped(
      RequestCommandId.printerCheckLine, [...Utils.u16ToBytes(line), 0x01]);

  /// Generate packets for image data
  /// Handles different row types (pixels, void, check) and auto-selects indexed packets
  static List<NiimbotPacket> writeImageData(
    dynamic encodedImage, {
    ImagePacketsGenerateOptions? options,
  }) {
    final opts = options ?? const ImagePacketsGenerateOptions();
    final out = <NiimbotPacket>[];

    // Get rowsData from encodedImage (support both Map and object)
    final rowsData = encodedImage is Map
        ? encodedImage['rowsData'] as List
        : encodedImage.rowsData as List;

    for (final d in rowsData) {
      final dataType = d is Map ? d['dataType'] : d.dataType;
      final rowNumber = d is Map ? d['rowNumber'] : d.rowNumber;
      final repeat = d is Map ? d['repeat'] : d.repeat;
      final blackPixelsCount =
          d is Map ? d['blackPixelsCount'] : d.blackPixelsCount;
      final rowData = d is Map ? d['rowData'] : d.rowData;

      if (dataType == 'pixels') {
        // Auto-select indexed packet for sparse rows (≤ 6 black pixels)
        if (blackPixelsCount <= 6 && !opts.noIndexPacket) {
          out.add(
            printBitmapRowIndexed(
              rowNumber,
              repeat,
              rowData!,
              opts.printheadPixels,
              countsMode: opts.countsMode,
            ),
          );
        } else {
          out.add(
            printBitmapRow(
              rowNumber,
              repeat,
              rowData!,
              opts.printheadPixels,
              countsMode: opts.countsMode,
            ),
          );
        }
        continue;
      }

      if (dataType == 'check' && opts.enableCheckLine) {
        out.add(checkLine(rowNumber));
        continue;
      }

      if (dataType == 'void') {
        out.add(printEmptySpace(rowNumber, repeat));
      }
    }

    return out;
  }

  static NiimbotPacket printTestPage() =>
      mapped(RequestCommandId.printTestPage);

  static NiimbotPacket labelPositioningCalibration(int value) =>
      mapped(RequestCommandId.labelPositioningCalibration, [value]);

  static NiimbotPacket startFirmwareUpgrade(String version) {
    // ignore: deprecated_member_use
    final regex = RegExp(r'^\d+\.\d+$');
    if (!regex.hasMatch(version)) {
      throw Exception('Invalid version format (x.x expected)');
    }

    final parts = version.split('.').map((p) => int.parse(p)).toList();
    return mapped(RequestCommandId.startFirmwareUpgrade, parts);
  }

  static NiimbotCrc32Packet sendFirmwareChecksum(int crc) {
    final p = NiimbotCrc32Packet(
      command: RequestCommandId.firmwareCrc,
      chunkNumber: 0,
      data: Uint8List.fromList(Utils.u32ToBytes(crc).toList()),
    );
    p.oneWay = true;
    return p;
  }

  static NiimbotCrc32Packet sendFirmwareChunk(int idx, Uint8List data) {
    final p = NiimbotCrc32Packet(
      command: RequestCommandId.firmwareChunk,
      chunkNumber: idx,
      data: data,
    );
    p.oneWay = true;
    return p;
  }

  static NiimbotCrc32Packet firmwareNoMoreChunks() {
    final p = NiimbotCrc32Packet(
      command: RequestCommandId.firmwareNoMoreChunks,
      chunkNumber: 0,
      data: Uint8List.fromList([1]),
    );
    p.oneWay = true;
    return p;
  }

  static NiimbotCrc32Packet firmwareCommit() {
    final p = NiimbotCrc32Packet(
      command: RequestCommandId.firmwareCommit,
      chunkNumber: 0,
      data: Uint8List.fromList([1]),
    );
    p.oneWay = true;
    return p;
  }

  /// Count black pixels for bitmap packet
  static List<int> _countPixelsForBitmapPacket(
    Uint8List data,
    int printheadPixels,
    String mode,
  ) {
    final total = _countBlackPixels(data);

    if (mode == 'total' || (mode == 'auto' && printheadPixels < 384)) {
      // Total mode: [0, low_byte, high_byte]
      return [0, total & 0xFF, (total >> 8) & 0xFF];
    } else {
      // Split mode: divide into 3 parts
      final chunkSize = (data.length / 3).ceil();
      final part1 =
          _countBlackPixels(data.sublist(0, chunkSize.clamp(0, data.length)));
      final part2 = _countBlackPixels(data.sublist(
          chunkSize.clamp(0, data.length),
          (chunkSize * 2).clamp(0, data.length)));
      final part3 = _countBlackPixels(
          data.sublist((chunkSize * 2).clamp(0, data.length), data.length));
      return [part1, part2, part3];
    }
  }

  /// Count black pixels in bitmap data (1 bit per pixel)
  static int _countBlackPixels(Uint8List data) {
    int count = 0;
    for (int byte in data) {
      for (int bit = 0; bit < 8; bit++) {
        if ((byte & (1 << (7 - bit))) != 0) {
          count++;
        }
      }
    }
    return count;
  }

  /// Get indexes of black pixels (for indexed packet)
  static Uint8List _indexPixels(Uint8List data) {
    final indexes = <int>[];
    int pixelIndex = 0;

    for (int byte in data) {
      for (int bit = 0; bit < 8; bit++) {
        if ((byte & (1 << (7 - bit))) != 0) {
          // Black pixel found - store as 2-byte big-endian
          indexes.add((pixelIndex >> 8) & 0xFF);
          indexes.add(pixelIndex & 0xFF);
        }
        pixelIndex++;
      }
    }

    return Uint8List.fromList(indexes);
  }
}
