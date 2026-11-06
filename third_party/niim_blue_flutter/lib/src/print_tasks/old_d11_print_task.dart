import 'abstract_print_task.dart';
import '../packets/packet_generator.dart';
import '../print_page.dart';

/// Print task for old D11 printer models (legacy devices)
class OldD11PrintTask extends AbstractPrintTask {
  OldD11PrintTask(super.abstraction, [super.options]);

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
        PacketGenerator.setPageSize2b(image.rows),
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
    return abstraction.waitUntilPrintFinishedByPageIndex(
      printOptions.totalPages ?? 1,
      printOptions.statusTimeoutMs,
    );
  }
}
