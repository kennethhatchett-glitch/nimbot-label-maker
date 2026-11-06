/// PrintPage class for building printable pages with text, QR, barcode, images
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr/qr.dart';
import 'package:image/image.dart' as img;
import 'utils/barcode.dart';

/// Print element options
class PrintElementOptions {
  final int x;
  final int y;
  final int? width;
  final int? height;
  final HAlignment align;
  final VAlignment vAlign;
  final double rotate; // Rotation angle in degrees

  const PrintElementOptions({
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.align = HAlignment.left,
    this.vAlign = VAlignment.top,
    this.rotate = 0,
  });
}

/// Horizontal alignment
enum HAlignment { left, center, right }

/// Vertical alignment
enum VAlignment { top, middle, bottom }

/// QR error correction level
enum QRErrorCorrection { low, medium, quartile, high }

/// Barcode encoding type
enum BarcodeEncoding { ean13, code128 }

/// Text options
class TextOptions extends PrintElementOptions {
  final int fontSize;
  final String? fontFamily;
  final FontWeight fontWeight;

  const TextOptions({
    required super.x,
    required super.y,
    super.width,
    super.height,
    super.align,
    super.vAlign,
    super.rotate,
    this.fontSize = 12,
    this.fontFamily,
    this.fontWeight = FontWeight.normal,
  });
}

/// QR code options
class QROptions extends PrintElementOptions {
  final QRErrorCorrection ecl;

  const QROptions({
    required super.x,
    required super.y,
    super.width,
    super.height,
    super.align,
    super.vAlign,
    super.rotate,
    this.ecl = QRErrorCorrection.medium,
  });
}

/// Barcode options
class BarcodeOptions extends PrintElementOptions {
  final BarcodeEncoding encoding;

  const BarcodeOptions({
    required super.x,
    required super.y,
    super.width,
    super.height,
    super.align,
    super.vAlign,
    super.rotate,
    this.encoding = BarcodeEncoding.ean13,
  });
}

/// Line options
class LineOptions {
  final int x;
  final int y;
  final int endX;
  final int endY;
  final int thickness;

  const LineOptions({
    required this.x,
    required this.y,
    required this.endX,
    required this.endY,
    this.thickness = 1,
  });
}

/// Image options
class ImageOptions extends PrintElementOptions {
  final List<int> data; // 1D array of 0/1 pixels
  final int imageWidth;
  final int imageHeight;

  const ImageOptions({
    required super.x,
    required super.y,
    super.width,
    super.height,
    super.align,
    super.vAlign,
    super.rotate,
    required this.data,
    required this.imageWidth,
    required this.imageHeight,
  });
}

/// Image from buffer options
class ImageFromBufferOptions extends PrintElementOptions {
  final Uint8List? buffer;
  final int threshold;

  const ImageFromBufferOptions({
    required super.x,
    required super.y,
    super.width,
    super.height,
    super.align,
    super.vAlign,
    super.rotate,
    this.buffer,
    this.threshold = 128,
  });
}

/// Encoded image for printing
class EncodedImage {
  final int cols;
  final int rows;
  final List<ImageRow> rowsData;

  const EncodedImage({
    required this.cols,
    required this.rows,
    required this.rowsData,
  });
}

/// Image row data
class ImageRow {
  final String dataType; // 'void' | 'pixels'
  final int rowNumber;
  int repeat;
  final int blackPixelsCount;
  final Uint8List? rowData;

  ImageRow({
    required this.dataType,
    required this.rowNumber,
    required this.repeat,
    required this.blackPixelsCount,
    this.rowData,
  });
}

/// Page orientation
enum PageOrientation { portrait, landscape }

/// PrintPage class to build printable pages with elements
///
/// Supports text, QR codes, barcodes, lines, and images.
/// Mimics fabric-object from web version.
class PrintPage {
  final int width;
  final int height;
  final PageOrientation orientation;
  late List<List<int>> pixels;

  PrintPage(int width, int height,
      [this.orientation = PageOrientation.portrait])
      : width = orientation == PageOrientation.landscape ? height : width,
        height = orientation == PageOrientation.landscape ? width : height {
    // Initialize pixel array (0 = white, 1 = black)
    pixels = List.generate(
      this.height,
      (_) => List.filled(this.width, 0),
    );
  }

  /// Add text to the page
  Future<void> addText(String text, TextOptions options) async {
    // Create text painter
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: options.fontSize.toDouble(),
        fontFamily: options.fontFamily,
        fontWeight: options.fontWeight,
        color: const Color(0xFF000000),
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout();

    final textWidth = textPainter.width.ceil();
    final textHeight = textPainter.height.ceil();

    // Calculate position based on alignment
    final x = _calculateX(options.x, textWidth, options.align).floor();
    final y = _calculateY(options.y, textHeight, options.vAlign).floor();
    final centerX = x + textWidth / 2;
    final centerY = y + textHeight / 2;

    // Create image to paint on
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Paint white background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, textWidth.toDouble(), textHeight.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // Paint text
    textPainter.paint(canvas, Offset.zero);

    // Convert to image
    final picture = recorder.endRecording();
    final image = picture.toImageSync(textWidth, textHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) return;

    // Convert RGBA to binary (1 = black, 0 = white)
    final pixelBytes = byteData.buffer.asUint8List();
    for (int row = 0; row < textHeight; row++) {
      for (int col = 0; col < textWidth; col++) {
        final offset = (row * textWidth + col) * 4;
        final r = pixelBytes[offset];
        final g = pixelBytes[offset + 1];
        final b = pixelBytes[offset + 2];
        final brightness = (r + g + b) ~/ 3;

        if (brightness < 128) {
          var drawX = x + col;
          var drawY = y + row;

          if (options.rotate != 0) {
            final rotated = _rotatePoint(
              drawX.toDouble(),
              drawY.toDouble(),
              centerX,
              centerY,
              options.rotate,
            );
            drawX = rotated['x']!.floor();
            drawY = rotated['y']!.floor();
          }

          if (drawX >= 0 && drawX < width && drawY >= 0 && drawY < height) {
            pixels[drawY][drawX] = 1; // Black
          }
        }
      }
    }
  }

  /// Add QR code to the page
  void addQR(String text, QROptions options) {
    final eclMap = {
      QRErrorCorrection.low: QrErrorCorrectLevel.L,
      QRErrorCorrection.medium: QrErrorCorrectLevel.M,
      QRErrorCorrection.quartile: QrErrorCorrectLevel.Q,
      QRErrorCorrection.high: QrErrorCorrectLevel.H,
    };

    final qrCode = QrCode.fromData(
      data: text,
      errorCorrectLevel: eclMap[options.ecl]!,
    );

    // Generate QR image with the best mask pattern
    final qrImage = QrImage(qrCode);

    final moduleCount = qrImage.moduleCount;
    int qrWidth = moduleCount;
    int qrHeight = moduleCount;
    int scaledWidth = qrWidth;
    int scaledHeight = qrHeight;

    if (options.width != null && options.height != null) {
      scaledWidth = options.width!;
      scaledHeight = options.height!;
    } else if (options.width != null) {
      scaledWidth = options.width!;
      scaledHeight = (options.width! * qrHeight / qrWidth).floor();
    } else if (options.height != null) {
      scaledHeight = options.height!;
      scaledWidth = (options.height! * qrWidth / qrHeight).floor();
    }

    final x = _calculateX(options.x, scaledWidth, options.align).floor();
    final y = _calculateY(options.y, scaledHeight, options.vAlign).floor();
    final centerX = x + scaledWidth / 2;
    final centerY = y + scaledHeight / 2;
    final rotate = options.rotate;

    for (int row = 0; row < scaledHeight; row++) {
      for (int col = 0; col < scaledWidth; col++) {
        final srcRow = (row * qrHeight / scaledHeight).floor();
        final srcCol = (col * qrWidth / scaledWidth).floor();

        if (qrImage.isDark(srcRow, srcCol)) {
          var drawX = x + col;
          var drawY = y + row;

          if (rotate != 0) {
            final rotated = _rotatePoint(
              drawX.toDouble(),
              drawY.toDouble(),
              centerX,
              centerY,
              rotate,
            );
            drawX = rotated['x']!.floor();
            drawY = rotated['y']!.floor();
          }

          if (drawX >= 0 && drawX < width && drawY >= 0 && drawY < height) {
            pixels[drawY][drawX] = 1; // Black
          }
        }
      }
    }
  }

  /// Add barcode to the page
  void addBarcode(String text, BarcodeOptions options) {
    String bandcode;

    if (options.encoding == BarcodeEncoding.ean13) {
      final result = ean13(text);
      bandcode = result.bandcode;
    } else {
      bandcode = code128b(text);
    }

    final barcodeWidth = bandcode.length;
    const barcodeHeight = 40;
    int scaledWidth = barcodeWidth;
    int scaledHeight = barcodeHeight;

    if (options.width != null && options.height != null) {
      scaledWidth = options.width!;
      scaledHeight = options.height!;
    } else if (options.width != null) {
      scaledWidth = options.width!;
      scaledHeight = (options.width! * barcodeHeight / barcodeWidth).floor();
    } else if (options.height != null) {
      scaledHeight = options.height!;
      scaledWidth = (options.height! * barcodeWidth / barcodeHeight).floor();
    }

    final x = _calculateX(options.x, scaledWidth, options.align).floor();
    final y = _calculateY(options.y, scaledHeight, options.vAlign).floor();
    final centerX = x + scaledWidth / 2;
    final centerY = y + scaledHeight / 2;
    final rotate = options.rotate;

    for (int row = 0; row < scaledHeight; row++) {
      for (int col = 0; col < scaledWidth; col++) {
        final srcCol = (col * barcodeWidth / scaledWidth).floor();
        final isBlack = bandcode[srcCol] == '1';

        if (isBlack) {
          var drawX = x + col;
          var drawY = y + row;

          if (rotate != 0) {
            final rotated = _rotatePoint(
              drawX.toDouble(),
              drawY.toDouble(),
              centerX,
              centerY,
              rotate,
            );
            drawX = rotated['x']!.floor();
            drawY = rotated['y']!.floor();
          }

          if (drawX >= 0 && drawX < width && drawY >= 0 && drawY < height) {
            pixels[drawY][drawX] = 1; // Black
          }
        }
      }
    }
  }

  /// Add line to the page
  void addLine(LineOptions options) {
    // Bresenham's line algorithm
    final dx = (options.endX - options.x).abs();
    final dy = (options.endY - options.y).abs();
    final sx = options.x < options.endX ? 1 : -1;
    final sy = options.y < options.endY ? 1 : -1;
    var err = dx - dy;

    var px = options.x;
    var py = options.y;

    while (true) {
      // Draw pixel with thickness
      for (var tx = -(options.thickness ~/ 2);
          tx <= (options.thickness ~/ 2);
          tx++) {
        for (var ty = -(options.thickness ~/ 2);
            ty <= (options.thickness ~/ 2);
            ty++) {
          final drawPx = px + tx;
          final drawPy = py + ty;
          if (drawPx >= 0 && drawPx < width && drawPy >= 0 && drawPy < height) {
            pixels[drawPy][drawPx] = 1; // Black
          }
        }
      }

      if (px == options.endX && py == options.endY) break;
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        px += sx;
      }
      if (e2 < dx) {
        err += dx;
        py += sy;
      }
    }
  }

  /// Add pixel data to the page
  void addPixelData(ImageOptions options) {
    final imageWidth = options.imageWidth;
    final imageHeight = options.imageHeight;
    int scaledWidth = imageWidth;
    int scaledHeight = imageHeight;

    if (options.width != null && options.height != null) {
      scaledWidth = options.width!;
      scaledHeight = options.height!;
    } else if (options.width != null) {
      scaledWidth = options.width!;
      scaledHeight = (options.width! * imageHeight / imageWidth).floor();
    } else if (options.height != null) {
      scaledHeight = options.height!;
      scaledWidth = (options.height! * imageWidth / imageHeight).floor();
    }

    final x = _calculateX(options.x, scaledWidth, options.align).floor();
    final y = _calculateY(options.y, scaledHeight, options.vAlign).floor();
    final centerX = x + scaledWidth / 2;
    final centerY = y + scaledHeight / 2;
    final rotate = options.rotate;

    for (int row = 0; row < scaledHeight; row++) {
      for (int col = 0; col < scaledWidth; col++) {
        final srcRow = (row * imageHeight / scaledHeight).floor();
        final srcCol = (col * imageWidth / scaledWidth).floor();
        final srcIndex = srcRow * imageWidth + srcCol;

        if (srcIndex < options.data.length && options.data[srcIndex] == 1) {
          var drawX = x + col;
          var drawY = y + row;

          if (rotate != 0) {
            final rotated = _rotatePoint(
              drawX.toDouble(),
              drawY.toDouble(),
              centerX,
              centerY,
              rotate,
            );
            drawX = rotated['x']!.floor();
            drawY = rotated['y']!.floor();
          }

          if (drawX >= 0 && drawX < width && drawY >= 0 && drawY < height) {
            pixels[drawY][drawX] = 1; // Black
          }
        }
      }
    }
  }

  /// Add image from buffer (PNG/JPG/BMP)
  void addImageFromBuffer(ImageFromBufferOptions options) {
    if (options.buffer == null) return;

    // Decode image
    final image = img.decodeImage(options.buffer!);
    if (image == null) return;

    // Convert to monochrome
    final grayscale = img.grayscale(image);
    final threshold = options.threshold;

    // Create pixel data
    final pixelData = <int>[];
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final luminance = pixel.r.toInt();
        pixelData.add(luminance < threshold ? 1 : 0);
      }
    }

    // Use addPixelData to add to page
    addPixelData(ImageOptions(
      x: options.x,
      y: options.y,
      width: options.width,
      height: options.height,
      align: options.align,
      vAlign: options.vAlign,
      rotate: options.rotate,
      data: pixelData,
      imageWidth: grayscale.width,
      imageHeight: grayscale.height,
    ));
  }

  /// Add image from URI (async)
  /// Fetches image from network and adds it to the page
  Future<void> addImageFromUri(
    String uri,
    ImageFromBufferOptions options,
  ) async {
    // Fetch image from URI
    final response = await http.get(Uri.parse(uri));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch image from $uri: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // Use addImageFromBuffer with fetched data
    addImageFromBuffer(ImageFromBufferOptions(
      buffer: response.bodyBytes,
      x: options.x,
      y: options.y,
      width: options.width,
      height: options.height,
      align: options.align,
      vAlign: options.vAlign,
      rotate: options.rotate,
      threshold: options.threshold,
    ));
  }

  /// Rotate a point around a center
  Map<String, double> _rotatePoint(
    double px,
    double py,
    double cx,
    double cy,
    double angleDegrees,
  ) {
    final angleRadians = angleDegrees * math.pi / 180;
    final cos = math.cos(angleRadians);
    final sin = math.sin(angleRadians);

    // Translate to origin
    final translatedX = px - cx;
    final translatedY = py - cy;

    // Rotate
    final rotatedX = translatedX * cos - translatedY * sin;
    final rotatedY = translatedX * sin + translatedY * cos;

    // Translate back
    return {
      'x': rotatedX + cx,
      'y': rotatedY + cy,
    };
  }

  /// Calculate X position based on alignment
  double _calculateX(int x, int elementWidth, HAlignment align) {
    switch (align) {
      case HAlignment.center:
        return x - elementWidth / 2;
      case HAlignment.right:
        return x - elementWidth.toDouble();
      case HAlignment.left:
        return x.toDouble();
    }
  }

  /// Calculate Y position based on vertical alignment
  double _calculateY(int y, int elementHeight, VAlignment vAlign) {
    switch (vAlign) {
      case VAlignment.middle:
        return y - elementHeight / 2;
      case VAlignment.bottom:
        return y - elementHeight.toDouble();
      case VAlignment.top:
        return y.toDouble();
    }
  }

  /// Convert page to EncodedImage for printing
  EncodedImage toEncodedImage() {
    final shouldRotate = orientation == PageOrientation.landscape;
    final outputWidth = shouldRotate ? height : width;
    final outputHeight = shouldRotate ? width : height;

    final rowsData = <ImageRow>[];

    for (int row = 0; row < outputHeight; row++) {
      int blackCount = 0;
      final rowData = Uint8List((outputWidth + 7) ~/ 8);

      for (int col = 0; col < outputWidth; col++) {
        // For landscape, rotate 90° counter-clockwise
        final srcX = shouldRotate ? (width - 1 - row) : col;
        final srcY = shouldRotate ? col : row;

        if (pixels[srcY][srcX] == 1) {
          blackCount++;
          final byteIndex = col ~/ 8;
          final bitIndex = col % 8;
          rowData[byteIndex] |= 1 << (7 - bitIndex);
        }
      }

      final newPart = ImageRow(
        dataType: blackCount > 0 ? 'pixels' : 'void',
        rowNumber: row,
        repeat: 1,
        blackPixelsCount: blackCount,
        rowData: blackCount > 0 ? rowData : null,
      );

      if (rowsData.isEmpty) {
        rowsData.add(newPart);
      } else {
        final lastPacket = rowsData.last;
        bool same = newPart.dataType == lastPacket.dataType;

        if (same && newPart.dataType == 'pixels') {
          same = newPart.rowData != null &&
              lastPacket.rowData != null &&
              newPart.rowData!.length == lastPacket.rowData!.length &&
              _uint8ListEquals(newPart.rowData!, lastPacket.rowData!);
        }

        if (same) {
          lastPacket.repeat++;
        } else {
          rowsData.add(newPart);
        }
      }
    }

    return EncodedImage(
      cols: outputWidth,
      rows: outputHeight,
      rowsData: rowsData,
    );
  }

  /// Helper to compare two Uint8Lists
  bool _uint8ListEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Convert page to preview image (PNG)
  Future<Uint8List> toPreviewImage() async {
    final shouldRotate = orientation == PageOrientation.landscape;
    final outputWidth = shouldRotate ? height : width;
    final outputHeight = shouldRotate ? width : height;

    // Create image
    final image = img.Image(width: outputWidth, height: outputHeight);

    for (int y = 0; y < outputHeight; y++) {
      for (int x = 0; x < outputWidth; x++) {
        // For landscape, rotate 90° counter-clockwise
        final srcX = shouldRotate ? (width - 1 - y) : x;
        final srcY = shouldRotate ? x : y;

        final isBlack = pixels[srcY][srcX] == 1;
        final color =
            isBlack ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255);
        image.setPixel(x, y, color);
      }
    }

    // Encode as PNG
    return Uint8List.fromList(img.encodePng(image));
  }
}
