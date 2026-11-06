import 'dart:async';
import 'dart:typed_data';
import 'package:synchronized/synchronized.dart';

import '../events.dart';
import '../packets/packet.dart';
import '../packets/packet_parser.dart';
import '../packets/packet_generator.dart';
import '../packets/dto.dart';
import '../packets/abstraction.dart';
import '../packets/payloads.dart';
import '../packets/commands.dart';
import '../utils.dart';
import '../printer_models.dart';
import '../print_tasks/abstract_print_task.dart';
import '../print_tasks/print_task_factory.dart';

/// Represents the connection result information
class ConnectionInfo {
  final String? deviceName;
  final ConnectResult result;

  ConnectionInfo({
    this.deviceName,
    required this.result,
  });

  @override
  String toString() => 'ConnectionInfo(device: $deviceName, result: $result)';
}

/// Abstract class representing a client with common functionality for interacting with a printer
/// Hardware interface must be defined after extending this class
abstract class NiimbotAbstractClient extends EventEmitter {
  late final Abstraction abstraction;
  late final PacketGenerator packetGenerator;
  final PrinterInfo info = PrinterInfo();
  Timer? _heartbeatTimer;
  int _heartbeatFails = 0;
  int _heartbeatIntervalMs = 2000;
  final Lock _mutex = Lock();
  bool debug = false;
  Uint8List _packetBuf = Uint8List(0);

  /// Packet interval in milliseconds (see https://github.com/MultiMote/niimblue/issues/5)
  int packetIntervalMs = 10;

  NiimbotAbstractClient() {
    abstraction = Abstraction(this);
    packetGenerator = PacketGenerator();
    on<ConnectionInfo>(ClientEvents.connected).listen((_) => startHeartbeat());
    on<void>(ClientEvents.disconnected).listen((_) {
      stopHeartbeat();
      _packetBuf = Uint8List(0);
    });
  }

  /// Connect to printer port
  Future<ConnectionInfo> connect();

  /// Disconnect from printer port
  Future<void> disconnect();

  /// Check if the client is connected
  bool isConnected();

  /// Send packet and wait for response for timeoutMs milliseconds
  ///
  /// If validResponseIds is defined, it will wait for packet with this command id.
  /// Throws PrintError when In_PrintError or In_NotSupported received.
  Future<NiimbotPacket> sendPacketWaitResponse(
    NiimbotPacket packet, [
    int timeoutMs = 1000,
  ]) async {
    return _mutex.synchronized(() async {
      if (packet.oneWay) {
        await sendPacket(packet, force: true);
        return NiimbotPacket(
          command: ResponseCommandId.inInvalid,
          data: Uint8List(0),
        );
      }

      // Patched: start listening BEFORE sending, so a fast reply that
      // arrives while the write is still completing is not missed.
      final reply = waitForPacket(
        packet.validResponseIds,
        catchErrorPackets: true,
        timeoutMs: timeoutMs,
      );
      try {
        await sendPacket(packet, force: true);
      } catch (e) {
        reply.ignore();
        rethrow;
      }
      return reply;
    });
  }

  /// Wait for response for timeoutMs milliseconds
  ///
  /// If ids is set, it will wait for packet with this command ids.
  /// Throws PrintError when In_PrintError or In_NotSupported received and catchErrorPackets is true.
  Future<NiimbotPacket> waitForPacket(
    List<ResponseCommandId> ids, {
    bool catchErrorPackets = true,
    int timeoutMs = 1000,
  }) {
    final completer = Completer<NiimbotPacket>();
    Timer? timeout;

    void listener(dynamic event) {
      if (event is! NiimbotPacket) return;

      final pktIn = event;
      final cmdIn = pktIn.command;

      if (ids.isEmpty ||
          ids.contains(cmdIn) ||
          (catchErrorPackets &&
              [ResponseCommandId.inPrintError, ResponseCommandId.inNotSupported]
                  .contains(cmdIn))) {
        timeout?.cancel();

        if (cmdIn == ResponseCommandId.inPrintError) {
          if (pktIn.data.length != 1) {
            completer
                .completeError(Exception('Invalid print error packet length'));
            return;
          }
          final errorCode = pktIn.data[0];
          completer
              .completeError(PrintError('Print error $errorCode', errorCode));
        } else if (cmdIn == ResponseCommandId.inNotSupported) {
          completer.completeError(PrintError('Feature not supported', 0));
        } else {
          completer.complete(pktIn);
        }
      }
    }

    timeout = Timer(Duration(milliseconds: timeoutMs), () {
      final idsHex =
          ids.map((id) => '0x${id.value.toRadixString(16)}').join(', ');
      completer.completeError(
          Exception('Timeout waiting response (waited for $idsHex)'));
    });

    final subscription =
        on<NiimbotPacket>(ClientEvents.packetReceived).listen(listener);

    completer.future.whenComplete(() {
      subscription.cancel();
      timeout?.cancel();
    });

    return completer.future;
  }

  /// Convert raw bytes to packet objects and fire events. Defragmentation included.
  void processRawPacket(Uint8List data) {
    if (data.isEmpty) {
      return;
    }

    // if (debug) {
    //   print('Processing raw packet: ${Utils.bytesToHex(data)}');
    // }

    _packetBuf = Uint8List.fromList([..._packetBuf, ...data]);

    if (_packetBuf.length > 1 &&
        !_hasSubarrayAtPos(_packetBuf, NiimbotPacket.head, 0)) {
      if (debug) {
        print(
            'Warning: Dropping invalid buffer ${Utils.bytesToHex(_packetBuf)}');
      }
      _packetBuf = Uint8List(0);
      return;
    }

    try {
      final packets = PacketParser.parsePacketBundle(_packetBuf);

      if (packets.isNotEmpty) {
        // if (debug) {
        //   print('Parsed ${packets.length} packet(s)');
        // }
        emit(ClientEvents.rawDataReceived, _packetBuf);

        for (var p in packets) {
          // if (debug) {
          //   print(
          //       'Emitting packet: cmd=0x${p.command.value.toRadixString(16)}, data=${Utils.bytesToHex(p.data)}');
          // }
          emit(ClientEvents.packetReceived, p);
        }

        _packetBuf = Uint8List(0);
      }
    } catch (e) {
      if (debug) {
        print('Packet parse error: $e');
      }

      // Try to find next valid packet header to recover
      int nextHeaderPos = -1;
      for (int i = 2; i < _packetBuf.length - 1; i++) {
        if (_hasSubarrayAtPos(_packetBuf, NiimbotPacket.head, i)) {
          nextHeaderPos = i;
          break;
        }
      }

      if (nextHeaderPos > 0) {
        if (debug) {
          print(
              'Found next header at position $nextHeaderPos, discarding $nextHeaderPos bytes');
        }
        _packetBuf = _packetBuf.sublist(nextHeaderPos);
      } else {
        // No valid header found, keep buffer for next data
        if (debug) {
          print(
              'No valid header found, keeping buffer: ${Utils.bytesToHex(_packetBuf)}');
        }
      }
    }
  }

  /// Helper to check subarray at position
  bool _hasSubarrayAtPos(Uint8List buf, Uint8List sub, int pos) {
    if (pos + sub.length > buf.length) return false;
    for (int i = 0; i < sub.length; i++) {
      if (buf[pos + i] != sub[i]) return false;
    }
    return true;
  }

  /// Send raw bytes to the printer port
  Future<void> sendRaw(Uint8List data, {bool force = false});

  /// Send packet
  Future<void> sendPacket(NiimbotPacket packet, {bool force = false}) async {
    if (debug) {
      print(
          'Sending packet: cmd=0x${packet.command.value.toRadixString(16)}, data=${Utils.bytesToHex(packet.data)}');
    }
    await sendRaw(packet.toBytes(), force: force);
    emit(ClientEvents.packetSent, packet);
  }

  /// Send "connect" packet and fetch the protocol version
  Future<void> initialNegotiate() async {
    info.connectResult = await abstraction.connectResult();
    info.protocolVersion = 0;

    if (info.connectResult == ConnectResult.connectedNew) {
      info.protocolVersion = 1;
    } else if (info.connectResult == ConnectResult.connectedV3) {
      final statusData = await abstraction.getPrinterStatusData();
      info.protocolVersion = statusData.protocolVersion;
    }
  }

  /// Fetches printer information and stores it
  Future<PrinterInfo> fetchPrinterInfo() async {
    info.modelId = await abstraction.getPrinterModel();

    try {
      info.serial = await abstraction.getPrinterSerialNumber();
    } catch (e) {
      if (debug) print('Error getting serial: $e');
    }

    try {
      info.mac = await abstraction.getPrinterBluetoothMacAddress();
    } catch (e) {
      if (debug) print('Error getting MAC: $e');
    }

    try {
      info.charge = await abstraction.getBatteryChargeLevel();
    } catch (e) {
      if (debug) print('Error getting battery: $e');
    }

    try {
      info.autoShutdownTime = await abstraction.getAutoShutDownTime();
    } catch (e) {
      if (debug) print('Error getting auto shutdown: $e');
    }

    try {
      info.labelType = await abstraction.getLabelType();
    } catch (e) {
      if (debug) print('Error getting label type: $e');
    }

    try {
      info.hardwareVersion = await abstraction.getHardwareVersion();
    } catch (e) {
      if (debug) print('Error getting hardware version: $e');
    }

    try {
      info.softwareVersion = await abstraction.getSoftwareVersion();
    } catch (e) {
      if (debug) print('Error getting software version: $e');
    }

    emit(ClientEvents.printerInfo, info);
    return info;
  }

  /// Get the stored information about the printer
  PrinterInfo getPrinterInfo() => info;

  /// Set interval for heartbeat
  void setHeartbeatInterval(int intervalMs) {
    _heartbeatIntervalMs = intervalMs;
  }

  /// Starts the heartbeat timer
  void startHeartbeat() {
    _heartbeatFails = 0;
    stopHeartbeat();

    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: _heartbeatIntervalMs),
      (_) async {
        if (!isConnected()) return;

        try {
          final data = await abstraction.heartbeat();
          _heartbeatFails = 0;
          emit(ClientEvents.heartbeat, data);
        } catch (e) {
          if (debug) print('Heartbeat failed: $e');
          _heartbeatFails++;
          emit(ClientEvents.heartbeatFailed, _heartbeatFails);
        }
      },
    );
  }

  /// Stops the heartbeat by clearing the interval timer
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Checks if the heartbeat timer has been started
  bool isHeartbeatStarted() => _heartbeatTimer != null;

  /// Get printer capabilities based on the printer model
  PrinterModelMeta? getModelMetadata() {
    if (info.modelId == null) {
      return null;
    }
    return getPrinterMetaById(info.modelId!);
  }

  /// Set the interval between packets in milliseconds
  void setPacketInterval(int milliseconds) {
    packetIntervalMs = milliseconds;
  }

  /// Enable some debug information logging
  void setDebug(bool value) {
    debug = value;
  }

  /// Determine print task type based on printer model
  PrintTaskName? getPrintTaskType() {
    final meta = getModelMetadata();
    if (meta == null) {
      return null;
    }
    return findPrintTask(meta.model, info.protocolVersion);
  }

  /// Create a new print task automatically based on detected printer model
  /// Similar to React Native: client.createPrintTask({ totalPages: 1, density: 3, ... })
  AbstractPrintTask? createPrintTask([PrintOptions? options]) {
    final taskName = getPrintTaskType();
    if (taskName == null) {
      return null;
    }

    return abstraction.newPrintTask(taskName, options);
  }

  // Stream getters for convenient event access
  Stream<ConnectionInfo> get onConnected =>
      on<ConnectionInfo>(ClientEvents.connected);
  Stream<void> get onDisconnected => on<void>(ClientEvents.disconnected);
  Stream<NiimbotPacket> get onPacketSent =>
      on<NiimbotPacket>(ClientEvents.packetSent);
  Stream<NiimbotPacket> get onPacketReceived =>
      on<NiimbotPacket>(ClientEvents.packetReceived);
  Stream<Uint8List> get onRawDataSent =>
      on<Uint8List>(ClientEvents.rawDataSent);
  Stream<Uint8List> get onRawDataReceived =>
      on<Uint8List>(ClientEvents.rawDataReceived);
  Stream<HeartbeatData> get onHeartbeat =>
      on<HeartbeatData>(ClientEvents.heartbeat);
  Stream<int> get onHeartbeatFailed => on<int>(ClientEvents.heartbeatFailed);
  Stream<PrinterInfo> get onPrinterInfo =>
      on<PrinterInfo>(ClientEvents.printerInfo);
  Stream<PrintStatus> get onPrintStatus =>
      on<PrintStatus>(ClientEvents.printStatus);
}
