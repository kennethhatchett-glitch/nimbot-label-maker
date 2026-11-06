import 'dart:async';
import 'dart:typed_data';

import 'package:niim_blue_flutter/src/print_tasks/print_task_factory.dart';

import 'packet.dart';
import 'packet_generator.dart';
import 'dto.dart';
import 'data_reader.dart';
import 'payloads.dart';
import 'commands.dart';
import '../client/abstract_client.dart';
import '../utils.dart';
import '../events.dart';
import '../print_tasks/abstract_print_task.dart';
import '../print_tasks/b1_print_task.dart';
import '../print_tasks/b21v1_print_task.dart';
import '../print_tasks/d110_print_task.dart';
import '../print_tasks/old_d11_print_task.dart';
import '../print_tasks/d110mv4_print_task.dart';

/// Packet sender and parser
class Abstraction {
  static const int defaultPacketTimeout = 1000; // Match React Native: 1_000ms

  final NiimbotAbstractClient client;
  int packetTimeout = defaultPacketTimeout;
  Timer? _statusPollTimer;
  Timer? _statusTimeoutTimer;

  Abstraction(this.client);

  NiimbotAbstractClient getClient() => client;

  int getPacketTimeout() => packetTimeout;

  void setPacketTimeout(int value) {
    packetTimeout = value;
  }

  void setDefaultPacketTimeout() {
    packetTimeout = defaultPacketTimeout;
  }

  /// Send packet and wait for response
  Future<NiimbotPacket> send(NiimbotPacket packet, [int? forceTimeout]) async {
    return client.sendPacketWaitResponse(
      packet,
      forceTimeout ?? packetTimeout,
    );
  }

  /// Send packet, wait for response, repeat if failed
  Future<NiimbotPacket> sendRepeatUntilSuccess(
    NiimbotPacket packet,
    int attempts, [
    int? forceTimeout,
  ]) async {
    Exception lastError = Exception('Unknown error');

    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        return await client.sendPacketWaitResponse(
          packet,
          forceTimeout ?? packetTimeout,
        );
      } catch (e) {
        if (client.debug) {
          print('Attempt ${attempt + 1} failed: $e');
        }
        lastError = e as Exception;
      }
    }

    throw lastError;
  }

  /// Send all packets
  Future<void> sendAll(List<NiimbotPacket> packets, [int? forceTimeout]) async {
    for (var p in packets) {
      await send(p, forceTimeout);
    }
  }

  /// Get print status
  Future<PrintStatus> getPrintStatus([int tries = 1]) async {
    final packet = await sendRepeatUntilSuccess(
      PacketGenerator.printStatus(),
      tries,
    );

    if (packet.data.length < 4) {
      throw Exception('Invalid print status packet length');
    }

    final r = SequentialDataReader(packet.data);
    final page = r.readI16();
    final pagePrintProgress = r.readI8();
    final pageFeedProgress = r.readI8();

    if (packet.dataLength == 10) {
      r.skip(2);
      final error = r.readI8();

      if (error != 0) {
        throw PrintError('Print error (packet flag)', error);
      }
    }

    return PrintStatus(
      page: page,
      pagePrintProgress: pagePrintProgress,
      pageFeedProgress: pageFeedProgress,
    );
  }

  /// Get connection result
  Future<ConnectResult> connectResult() async {
    final packet = await send(PacketGenerator.connect());
    if (packet.data.isEmpty) {
      throw Exception('Invalid connect response');
    }
    return ConnectResult.fromValue(packet.data[0]);
  }

  /// Get printer status data
  Future<PrinterStatusData> getPrinterStatusData() async {
    int protocolVersion = 0;
    final packet = await send(PacketGenerator.getPrinterStatusData());
    int supportColor = 0;

    if (packet.dataLength > 12) {
      supportColor = packet.data[10];

      final n = packet.data[11] * 100 + packet.data[12];

      if (n >= 204 && n < 300) {
        protocolVersion = 3;
      } else if (n < 300 || n >= 302) {
        protocolVersion = n >= 302 ? 5 : 0;
      } else {
        protocolVersion = 4;
      }
    }

    return PrinterStatusData(
      supportColor: supportColor,
      protocolVersion: protocolVersion,
    );
  }

  /// Get printer model
  Future<int> getPrinterModel() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(8)); // PrinterModelId
    if (packet.data.isEmpty) {
      throw Exception('Invalid printer model response');
    }

    if (packet.data.length == 1) {
      return packet.data[0] << 8;
    }

    if (packet.data.length != 2) {
      throw Exception('Invalid printer model data length');
    }

    return Utils.bytesToU16(packet.data);
  }

  /// Process RFID info from packet
  RfidInfo _processRfidInfo(NiimbotPacket packet) {
    if (packet.dataLength == 1) {
      return RfidInfo(
        tagPresent: false,
        uuid: '',
        barCode: '',
        serialNumber: '',
        allPaper: -1,
        usedPaper: -1,
        consumablesType: LabelType.invalid,
      );
    }

    final r = SequentialDataReader(packet.data);
    final uuid = Utils.bytesToHex(r.readBytes(8)).replaceAll(' ', '');
    final barCode = r.readVString();
    final serialNumber = r.readVString();
    final allPaper = r.readI16();
    final usedPaper = r.readI16();
    final consumablesType = LabelType.fromValue(r.readI8());
    int? capacity;

    if (r.canRead(2)) {
      capacity = r.readI16();
    }

    return RfidInfo(
      tagPresent: true,
      uuid: uuid,
      barCode: barCode,
      serialNumber: serialNumber,
      allPaper: allPaper,
      usedPaper: usedPaper,
      consumablesType: consumablesType,
      capacity: capacity,
    );
  }

  /// Read paper NFC tag info
  Future<RfidInfo> rfidInfo() async {
    final packet = await send(PacketGenerator.rfidInfo());
    return _processRfidInfo(packet);
  }

  /// Read ribbon NFC tag info
  Future<RfidInfo> rfidInfo2() async {
    final packet = await send(PacketGenerator.rfidInfo2());
    return _processRfidInfo(packet);
  }

  /// Heartbeat
  Future<HeartbeatData> heartbeat() async {
    final packet = await send(PacketGenerator.heartbeat(1), 500);

    final info = HeartbeatData(
      paperState: -1,
      rfidReadState: -1,
      lidClosed: false,
      powerLevel: BatteryChargeLevel.charge0,
    );

    final len = packet.dataLength;
    final r = SequentialDataReader(packet.data);

    if (len == 10) {
      // D110
      r.skip(8);
      info.lidClosed = r.readBool();
      info.powerLevel = BatteryChargeLevel.fromValue(r.readI8());
    } else if (len == 20) {
      r.skip(18);
      info.paperState = r.readI8();
      info.rfidReadState = r.readI8();
    } else if (len == 19) {
      r.skip(15);
      info.lidClosed = r.readBool();
      info.powerLevel = BatteryChargeLevel.fromValue(r.readI8());
      info.paperState = r.readI8();
      info.rfidReadState = r.readI8();
    } else if (len == 13) {
      // B1
      r.skip(9);
      info.lidClosed = r.readBool();
      info.powerLevel = BatteryChargeLevel.fromValue(r.readI8());
      info.paperState = r.readI8();
      info.rfidReadState = r.readI8();
    } else {
      throw Exception('Invalid heartbeat length: $len');
    }

    final model = client.getPrinterInfo().modelId;

    if (model != null &&
        ![512, 514, 513, 2304, 1792, 3584, 5120, 2560, 3840, 4352, 272]
            .contains(model)) {
      info.lidClosed = !info.lidClosed;
    }

    return info;
  }

  /// Get battery charge level
  Future<BatteryChargeLevel> getBatteryChargeLevel() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(10)); // BatteryChargeLevel
    if (packet.data.length != 1) {
      throw Exception('Invalid battery response');
    }
    return BatteryChargeLevel.fromValue(packet.data[0]);
  }

  /// Get auto shutdown time
  Future<AutoShutdownTime> getAutoShutDownTime() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(7)); // AutoShutdownTime
    if (packet.data.length != 1) {
      throw Exception('Invalid auto shutdown response');
    }
    return AutoShutdownTime.fromValue(packet.data[0]);
  }

  /// Get software version (may be wrong, format varies between models)
  Future<String> getSoftwareVersion() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(9)); // SoftWareVersion
    if (packet.data.length != 2) {
      throw Exception('Invalid software version response');
    }

    final v1 = packet.data[1] / 100 + packet.data[0];
    final v2 = (packet.data[0] * 256 + packet.data[1]) / 100.0;

    return '0x${Utils.bytesToHex(packet.data).replaceAll(' ', '')} (${v1.toStringAsFixed(2)} or ${v2.toStringAsFixed(2)})';
  }

  /// Get hardware version (may be wrong, format varies between models)
  Future<String> getHardwareVersion() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(12)); // HardWareVersion
    if (packet.data.length != 2) {
      throw Exception('Invalid hardware version response');
    }

    final v1 = packet.data[1] / 100 + packet.data[0];
    final v2 = (packet.data[0] * 256 + packet.data[1]) / 100.0;

    return '0x${Utils.bytesToHex(packet.data).replaceAll(' ', '')} (${v1.toStringAsFixed(2)} or ${v2.toStringAsFixed(2)})';
  }

  /// Set auto shutdown time
  Future<void> setAutoShutDownTime(AutoShutdownTime time) async {
    await send(PacketGenerator.setAutoShutDownTime(time));
  }

  /// Get label type
  Future<LabelType> getLabelType() async {
    final packet = await send(PacketGenerator.getPrinterInfo(3)); // LabelType
    if (packet.data.length != 1) {
      throw Exception('Invalid label type response');
    }
    return LabelType.fromValue(packet.data[0]);
  }

  /// Get printer serial number
  Future<String> getPrinterSerialNumber() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(11)); // SerialNumber
    if (packet.data.isEmpty) {
      throw Exception('Invalid serial number response');
    }

    if (packet.data.length < 4) {
      return '-1';
    }

    if (packet.data.length >= 8) {
      return Utils.bytesToString(packet.data);
    }

    return Utils.bytesToHex(packet.data.sublist(0, 4))
        .replaceAll(' ', '')
        .toUpperCase();
  }

  /// Get printer Bluetooth MAC address
  Future<String> getPrinterBluetoothMacAddress() async {
    final packet =
        await send(PacketGenerator.getPrinterInfo(13)); // BluetoothAddress
    if (packet.data.isEmpty) {
      throw Exception('Invalid MAC address response');
    }
    return Utils.bytesToHex(Uint8List.fromList(packet.data.reversed.toList()))
        .replaceAll(' ', ':');
  }

  /// Get sound enabled status
  Future<bool> isSoundEnabled(int soundType) async {
    final packet = await send(PacketGenerator.getSoundSettings(soundType));
    if (packet.data.length != 3) {
      throw Exception('Invalid sound settings response: expected 3 bytes');
    }
    return packet.data[2] != 0;
  }

  /// Set sound enabled
  Future<void> setSoundEnabled(int soundType, bool value) async {
    await send(PacketGenerator.setSoundSettings(soundType, value));
  }

  /// Clear settings (reset printer)
  Future<void> printerReset() async {
    await send(PacketGenerator.printerReset());
  }

  /// Print end
  Future<bool> printEnd() async {
    final response = await send(PacketGenerator.printEnd());
    if (response.data.length != 1) {
      throw Exception('Invalid print end response');
    }
    return response.data[0] == 1;
  }

  /// Label positioning calibration
  /// When 1 or 2 sent to B1, it starts to throw out some paper (~15cm)
  Future<bool> labelPositioningCalibration(int value) async {
    final response =
        await send(PacketGenerator.labelPositioningCalibration(value));
    if (response.data.length != 1) {
      throw Exception('Invalid calibration response');
    }
    return response.data[0] == 1;
  }

  /// Firmware upgrade
  Future<void> firmwareUpgrade(Uint8List data, String version) async {
    // Calculate CRC32
    final crc = Utils.crc32(data);
    await send(PacketGenerator.startFirmwareUpgrade(version));

    // Wait for CRC request
    await client.waitForPacket(
      [ResponseCommandId.inRequestFirmwareCrc],
      catchErrorPackets: true,
      timeoutMs: 5000,
    );

    // Send CRC
    await send(PacketGenerator.sendFirmwareChecksum(crc));

    const chunkSize = 200;
    final totalChunks = data.length ~/ chunkSize;

    // Send chunks
    while (true) {
      final packet = await client.waitForPacket(
        [
          ResponseCommandId.inRequestFirmwareChunk,
          ResponseCommandId.inFirmwareResult
        ],
        catchErrorPackets: true,
        timeoutMs: 5000,
      );

      if (packet.command == ResponseCommandId.inFirmwareResult) {
        throw Exception('Unexpected firmware result');
      }

      if (packet is! NiimbotCrc32Packet) {
        throw Exception('Not a firmware packet');
      }

      if (packet.chunkNumber * chunkSize >= data.length) {
        break;
      }

      final offset = packet.chunkNumber * chunkSize;
      final end =
          (offset + chunkSize > data.length) ? data.length : offset + chunkSize;
      final chunk = data.sublist(offset, end);

      await send(PacketGenerator.sendFirmwareChunk(packet.chunkNumber, chunk));

      client.emit(
        'firmwareProgress',
        FirmwareProgressEvent(
          current: packet.chunkNumber,
          total: totalChunks,
        ),
      );
    }

    // Send no more chunks
    await send(PacketGenerator.firmwareNoMoreChunks());

    // Wait for check result
    final uploadResult = await client.waitForPacket(
      [ResponseCommandId.inFirmwareCheckResult],
      catchErrorPackets: true,
      timeoutMs: 5000,
    );

    if (uploadResult.data.length != 1 || uploadResult.data[0] != 1) {
      throw Exception('Firmware check error (maybe CRC does not match)');
    }

    // Commit firmware
    await send(PacketGenerator.firmwareCommit());

    // Wait for final result
    final firmwareResult = await client.waitForPacket(
      [ResponseCommandId.inFirmwareResult],
      catchErrorPackets: true,
      timeoutMs: 5000,
    );

    if (firmwareResult.data.length != 1 || firmwareResult.data[0] != 1) {
      throw Exception('Firmware error');
    }
  }

  /// Wait until print finished by status poll
  Future<void> waitUntilPrintFinishedByStatusPoll(
    int pagesToPrint, [
    int pollIntervalMs = 300,
  ]) async {
    final completer = Completer<void>();

    client.emit(
        'printStatus',
        PrintStatus(
          page: 1,
          pagePrintProgress: 0,
          pageFeedProgress: 0,
        ));

    _statusPollTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) async {
        try {
          final status = await getPrintStatus(2);

          client.emit('printStatus', status);

          if (status.page == pagesToPrint &&
              status.pagePrintProgress == 100 &&
              status.pageFeedProgress == 100) {
            _statusPollTimer?.cancel();
            completer.complete();
          }
        } catch (e) {
          _statusPollTimer?.cancel();
          completer.completeError(e);
        }
      },
    );

    return completer.future;
  }

  /// Wait until print finished by print end poll
  /// Poll printer every pollIntervalMs and resolve when printer accepts printEnd
  /// PrintEnd call is not needed after this function is done running
  Future<void> waitUntilPrintFinishedByPrintEndPoll(
    int pagesToPrint, [
    int pollIntervalMs = 500,
  ]) async {
    final completer = Completer<void>();

    client.emit(
        'printStatus',
        PrintStatus(
          page: 1,
          pagePrintProgress: 0,
          pageFeedProgress: 0,
        ));

    _statusPollTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) async {
        try {
          final printEndDone = await printEnd();

          if (!printEndDone) {
            client.emit(
                'printStatus',
                PrintStatus(
                  page: 1,
                  pagePrintProgress: 0,
                  pageFeedProgress: 0,
                ));
          } else {
            client.emit(
                'printStatus',
                PrintStatus(
                  page: pagesToPrint,
                  pagePrintProgress: 100,
                  pageFeedProgress: 100,
                ));
            _statusPollTimer?.cancel();
            completer.complete();
          }
        } catch (e) {
          _statusPollTimer?.cancel();
          completer.completeError(e);
        }
      },
    );

    return completer.future;
  }

  /// Wait until print finished by page index
  /// Listen for PageIndex packets and resolve when page equals pagesToPrint
  Future<void> waitUntilPrintFinishedByPageIndex(
    int pagesToPrint, [
    int? statusTimeoutMs,
  ]) async {
    final completer = Completer<void>();
    StreamSubscription<NiimbotPacket>? subscription;

    // Emit initial progress
    client.emit(
        'printStatus',
        PrintStatus(
          page: 1,
          pagePrintProgress: 0,
          pageFeedProgress: 0,
        ));

    // Setup timeout
    _statusTimeoutTimer =
        Timer(Duration(milliseconds: statusTimeoutMs ?? 5000), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(Exception('Timeout waiting print status'));
      }
    });

    // Listen for PageIndex packets
    subscription = client.onPacketReceived.listen((packet) {
      if (packet.command == ResponseCommandId.inPrinterPageIndex) {
        if (packet.data.length == 2) {
          final page = Utils.bytesToI16(packet.data);

          client.emit(
              'printStatus',
              PrintStatus(
                page: page,
                pagePrintProgress: 100,
                pageFeedProgress: 100,
              ));

          // Reset timeout on each packet received
          _statusTimeoutTimer?.cancel();
          _statusTimeoutTimer =
              Timer(Duration(milliseconds: statusTimeoutMs ?? 5000), () {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer
                  .completeError(Exception('Timeout waiting print status'));
            }
          });

          if (page == pagesToPrint) {
            _statusTimeoutTimer?.cancel();
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        }
      }
    });

    return completer.future;
  }

  /// Create a new print task
  AbstractPrintTask newPrintTask(PrintTaskName name, [PrintOptions? options]) {
    switch (name) {
      case PrintTaskName.d11V1:
        return OldD11PrintTask(this, options);
      case PrintTaskName.d110:
        return D110PrintTask(this, options);
      case PrintTaskName.b1:
        return B1PrintTask(this, options);
      case PrintTaskName.b21V1:
        return B21V1PrintTask(this, options);
      case PrintTaskName.d110mV4:
        return D110MV4PrintTask(this, options);
    }
  }

  /// Dispose timers
  void dispose() {
    _statusPollTimer?.cancel();
    _statusTimeoutTimer?.cancel();
  }
}
