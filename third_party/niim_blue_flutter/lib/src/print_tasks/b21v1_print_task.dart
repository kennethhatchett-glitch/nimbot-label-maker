import 'abstract_print_task.dart';
import '../packets/packet_generator.dart';
import '../print_page.dart';

/// Print task for B21V1 printer model
class B21V1PrintTask extends AbstractPrintTask {
  B21V1PrintTask(super.abstraction, [super.options]);

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
  Future<void> printPage(EncodedImage image, [int quantity = 1]) async {
    checkAddPage(quantity);

    for (int i = 0; i < quantity; i++) {
      await abstraction.sendAll(
        [
          // PacketGenerator.printClear(), // Commented in React Native
          PacketGenerator.pageStart(),
          PacketGenerator.setPageSize4b(image.rows, image.cols),
          ...PacketGenerator.writeImageData(
            image,
            options: ImagePacketsGenerateOptions(
              countsMode: 'total',
              enableCheckLine: true,
              printheadPixels: printheadPixels(),
            ),
          ),
          PacketGenerator.pageEnd(),
        ],
        printOptions.pageTimeoutMs,
      );
    }
  }

  @override
  Future<void> waitForFinished() {
    abstraction.setPacketTimeout(
      printOptions.statusTimeoutMs ?? PrintOptionsDefaults.statusTimeoutMs,
    );

    return abstraction
        .waitUntilPrintFinishedByPrintEndPoll(
          printOptions.totalPages ?? PrintOptionsDefaults.totalPages,
          printOptions.statusPollIntervalMs ??
              PrintOptionsDefaults.statusPollIntervalMs,
        )
        .whenComplete(() => abstraction.setDefaultPacketTimeout());
  }
}
