import 'abstract_print_task.dart';
import '../packets/packet_generator.dart';
import '../print_page.dart';

/// Print task for D110 (old firmware) printer
class D110PrintTask extends AbstractPrintTask {
  D110PrintTask(super.abstraction, [super.options]);

  @override
  Future<void> printInit() {
    return abstraction.sendAll([
      PacketGenerator.setDensity(
        printOptions.density ?? PrintOptionsDefaults.density,
      ),
      PacketGenerator.setLabelType(
        (printOptions.labelType ?? PrintOptionsDefaults.labelType).value,
      ),
      PacketGenerator.printStart1b(),
    ]);
  }

  @override
  Future<void> printPage(EncodedImage image, [int quantity = 1]) {
    checkAddPage(quantity);

    return abstraction.sendAll(
      [
        PacketGenerator.printClear(),
        PacketGenerator.pageStart(),
        PacketGenerator.setPageSize4b(image.rows, image.cols),
        PacketGenerator.setPrintQuantity(quantity),
        ...PacketGenerator.writeImageData(
          image,
          options: ImagePacketsGenerateOptions(
            printheadPixels: printheadPixels(),
          ),
        ),
        PacketGenerator.pageEnd(),
      ],
      printOptions.pageTimeoutMs,
    );
  }

  @override
  Future<void> waitForFinished() {
    abstraction.setPacketTimeout(
      printOptions.statusTimeoutMs ?? PrintOptionsDefaults.statusTimeoutMs,
    );

    return abstraction
        .waitUntilPrintFinishedByStatusPoll(
          printOptions.totalPages ?? PrintOptionsDefaults.totalPages,
          printOptions.statusPollIntervalMs ??
              PrintOptionsDefaults.statusPollIntervalMs,
        )
        .whenComplete(() => abstraction.setDefaultPacketTimeout());
  }
}
