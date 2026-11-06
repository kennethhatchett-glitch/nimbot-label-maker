/// Commands IDs from client to printer
enum RequestCommandId {
  invalid(-1),

  /// Entire packet should be prefixed with 0x03
  connect(0xc1),
  cancelPrint(0xda),
  calibrateHeight(0x59),
  heartbeat(0xdc),
  labelPositioningCalibration(0x8e),
  pageEnd(0xe3),
  printerLog(0x05),
  pageStart(0x03),
  printBitmapRow(0x85),

  /// Sent if black pixels < 6
  printBitmapRowIndexed(0x83),
  printClear(0x20),
  printEmptyRow(0x84),
  printEnd(0xf3),
  printerInfo(0x40),
  printerConfig(0xaf),
  printerStatusData(0xa5),
  printerReset(0x28),
  printQuantity(0x15),
  printStart(0x01),
  printStatus(0xa3),
  rfidInfo(0x1a),
  rfidInfo2(0x1c),
  rfidSuccessTimes(0x54),
  setAutoShutdownTime(0x27),
  setDensity(0x21),
  setLabelType(0x23),

  /// 2, 4 or 6 bytes
  setPageSize(0x13),
  soundSettings(0x58),

  /// some info request (niimbot app), 01 long 02 short
  antiFake(0x0b),

  /// same as GetVolumeLevel???
  writeRFID(0x70),
  printTestPage(0x5a),
  startFirmwareUpgrade(0xf5),
  firmwareCrc(0x91),
  firmwareCommit(0x92),
  firmwareChunk(0x9b),
  firmwareNoMoreChunks(0x9c),
  printerCheckLine(0x86),
  getCurrentTimeFormat(0x12),
  printerConfig2(0x07),
  getKeyFunction(0x09),
  getPrintQuality(0x0d),
  getPrinterConfigurationWifi(0xa2);

  const RequestCommandId(this.value);
  final int value;

  static RequestCommandId fromValue(int value) {
    return RequestCommandId.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RequestCommandId.invalid,
    );
  }
}

/// Commands IDs from printer to client
enum ResponseCommandId {
  inInvalid(-1),
  inNotSupported(0x00),
  inConnect(0xc2),
  inCalibrateHeight(0x69),
  inCancelPrint(0xd0),
  inAntiFake(0x0c),
  inHeartbeatAdvanced1(0xdd),
  inHeartbeatBasic(0xde),
  inHeartbeatUnknown(0xdf),
  inHeartbeatAdvanced2(0xd9),
  inLabelPositioningCalibration(0x8f),
  inPageStart(0x04),
  inPrintClear(0x30),

  /// Sent by some printers after PageEnd along with In_PageEnd
  inPrinterCheckLine(0xd3),
  inPrintEnd(0xf4),
  inPrinterConfig(0xbf),
  inPrinterLog(0x06),
  inPrinterInfoAutoShutDownTime(0x47),
  inPrinterInfoBluetoothAddress(0x4d),
  inPrinterInfoSpeed(0x42),
  inPrinterInfoDensity(0x41),
  inPrinterInfoLanguage(0x46),
  inPrinterInfoChargeLevel(0x4a),
  inPrinterInfoHardWareVersion(0x4c),
  inPrinterInfoLabelType(0x43),
  inPrinterInfoPrinterCode(0x48),
  inPrinterInfoSerialNumber(0x4b),
  inPrinterInfoSoftWareVersion(0x49),
  inPrinterInfoArea(0x4f),
  inPrinterStatusData(0xb5),
  inPrinterReset(0x38),
  inPrintStatus(0xb3),

  /// For example, received after SetPageSize when page print is not started
  inPrintError(0xdb),
  inPrintQuantity(0x16),
  inPrintStart(0x02),
  inRfidInfo(0x1b),
  inRfidInfo2(0x1d),
  inRfidSuccessTimes(0x64),
  inSetAutoShutdownTime(0x37),
  inSetDensity(0x31),
  inSetLabelType(0x33),
  inSetPageSize(0x14),
  inSoundSettings(0x68),
  inPageEnd(0xe4),
  inPrinterPageIndex(0xe0),
  inPrintTestPage(0x6a),
  inWriteRFID(0x71),
  inStartFirmwareUpgrade(0xf6),
  inRequestFirmwareCrc(0x90),
  inRequestFirmwareChunk(0x9a),
  inFirmwareCheckResult(0x9d),
  inFirmwareResult(0x9e),

  /// Sent before In_PrinterCheckLine
  inResetTimeout(0xc6),
  inGetCurrentTimeFormat(0x11),
  inPrinterConfig2(0x08),
  inGetKeyFunction(0x0a),
  inGetPrintQuality(0x0d),
  inGetPrinterConfigurationWifi(0xb2);

  const ResponseCommandId(this.value);
  final int value;

  static ResponseCommandId fromValue(int value) {
    return ResponseCommandId.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ResponseCommandId.inInvalid,
    );
  }
}

/// Map request id to response id. null means no response expected (one way).
final Map<RequestCommandId, List<ResponseCommandId>?> commandsMap = {
  RequestCommandId.invalid: null,
  RequestCommandId.printBitmapRow: null,
  RequestCommandId.printBitmapRowIndexed: null,
  RequestCommandId.printEmptyRow: null,
  RequestCommandId.connect: [ResponseCommandId.inConnect],
  RequestCommandId.cancelPrint: [ResponseCommandId.inCancelPrint],
  RequestCommandId.calibrateHeight: [ResponseCommandId.inCalibrateHeight],
  RequestCommandId.heartbeat: [
    ResponseCommandId.inHeartbeatBasic,
    ResponseCommandId.inHeartbeatUnknown,
    ResponseCommandId.inHeartbeatAdvanced1,
    ResponseCommandId.inHeartbeatAdvanced2
  ],
  RequestCommandId.labelPositioningCalibration: [
    ResponseCommandId.inLabelPositioningCalibration
  ],
  RequestCommandId.pageEnd: [ResponseCommandId.inPageEnd],
  RequestCommandId.printerLog: [ResponseCommandId.inPrinterLog],
  RequestCommandId.pageStart: [ResponseCommandId.inPageStart],
  RequestCommandId.printClear: [ResponseCommandId.inPrintClear],
  RequestCommandId.printEnd: [ResponseCommandId.inPrintEnd],
  RequestCommandId.printerInfo: [
    ResponseCommandId.inPrinterInfoArea,
    ResponseCommandId.inPrinterInfoAutoShutDownTime,
    ResponseCommandId.inPrinterInfoBluetoothAddress,
    ResponseCommandId.inPrinterInfoChargeLevel,
    ResponseCommandId.inPrinterInfoDensity,
    ResponseCommandId.inPrinterInfoHardWareVersion,
    ResponseCommandId.inPrinterInfoLabelType,
    ResponseCommandId.inPrinterInfoLanguage,
    ResponseCommandId.inPrinterInfoPrinterCode,
    ResponseCommandId.inPrinterInfoSerialNumber,
    ResponseCommandId.inPrinterInfoSoftWareVersion,
    ResponseCommandId.inPrinterInfoSpeed,
  ],
  RequestCommandId.printerConfig: [ResponseCommandId.inPrinterConfig],
  RequestCommandId.printerStatusData: [ResponseCommandId.inPrinterStatusData],
  RequestCommandId.printerReset: [ResponseCommandId.inPrinterReset],
  RequestCommandId.printQuantity: [ResponseCommandId.inPrintQuantity],
  RequestCommandId.printStart: [ResponseCommandId.inPrintStart],
  RequestCommandId.printStatus: [ResponseCommandId.inPrintStatus],
  RequestCommandId.rfidInfo: [ResponseCommandId.inRfidInfo],
  RequestCommandId.rfidInfo2: [ResponseCommandId.inRfidInfo2],
  RequestCommandId.rfidSuccessTimes: [ResponseCommandId.inRfidSuccessTimes],
  RequestCommandId.setAutoShutdownTime: [
    ResponseCommandId.inSetAutoShutdownTime
  ],
  RequestCommandId.setDensity: [ResponseCommandId.inSetDensity],
  RequestCommandId.setLabelType: [ResponseCommandId.inSetLabelType],
  RequestCommandId.setPageSize: [ResponseCommandId.inSetPageSize],
  RequestCommandId.soundSettings: [ResponseCommandId.inSoundSettings],
  RequestCommandId.antiFake: [ResponseCommandId.inAntiFake],
  RequestCommandId.writeRFID: [ResponseCommandId.inWriteRFID],
  RequestCommandId.printTestPage: [ResponseCommandId.inPrintTestPage],
  RequestCommandId.startFirmwareUpgrade: [
    ResponseCommandId.inStartFirmwareUpgrade
  ],
  RequestCommandId.firmwareCrc: null,
  RequestCommandId.firmwareChunk: null,
  RequestCommandId.firmwareNoMoreChunks: null,
  RequestCommandId.firmwareCommit: null,
  RequestCommandId.printerCheckLine: [ResponseCommandId.inPrinterCheckLine],
  RequestCommandId.getCurrentTimeFormat: [
    ResponseCommandId.inGetCurrentTimeFormat
  ],
  RequestCommandId.printerConfig2: [ResponseCommandId.inPrinterConfig2],
  RequestCommandId.getKeyFunction: [ResponseCommandId.inGetKeyFunction],
  RequestCommandId.getPrintQuality: [ResponseCommandId.inGetPrintQuality],
  RequestCommandId.getPrinterConfigurationWifi: [
    ResponseCommandId.inGetPrinterConfigurationWifi
  ],
};

/// Firmware exchange packets
class FirmwareExchangePackets {
  static final List<RequestCommandId> tx = [
    RequestCommandId.firmwareChunk,
    RequestCommandId.firmwareCrc,
    RequestCommandId.firmwareNoMoreChunks,
    RequestCommandId.firmwareCommit,
  ];

  static final List<ResponseCommandId> rx = [
    ResponseCommandId.inRequestFirmwareCrc,
    ResponseCommandId.inRequestFirmwareChunk,
    ResponseCommandId.inFirmwareCheckResult,
    ResponseCommandId.inFirmwareResult,
  ];
}
