# Flutter NiimBlue Library

A Flutter library for Bluetooth LE printing with NIIMBOT thermal printers. Features automatic printer model detection, rich content rendering (text, QR codes, barcodes, images), and comprehensive print control.

## ✨ Features

- 🔍 **Auto-detect printer models** - Automatically selects the correct print task based on connected printer
- 📱 **BLE Communication** - Direct Bluetooth Low Energy connection to NIIMBOT printers
- 🎨 **Rich Content Support**:
  - Text rendering with Flutter Canvas
  - QR codes with error correction levels
  - Barcodes (EAN13, CODE128)
  - Images from files or memory
  - Lines and custom pixel data
- 🖼️ **Print Preview** - Generate PNG previews before printing
- 📏 **Flexible Layout** - Pixel-perfect positioning with alignment options
- 🔄 **Multiple Printer Support** - B1, B21, D110, D11 and more

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  niim_blue_flutter: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## 🔧 Setup

### Android Setup

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

Set minimum SDK version to 21 in `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App needs Bluetooth to connect to NIIMBOT printers</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>App needs Bluetooth to connect to NIIMBOT printers</string>
```

Set minimum iOS version to 12.0 in `ios/Podfile`:

```ruby
platform :ios, '12.0'
```

Install CocoaPods dependencies:

```bash
cd ios && pod install
```

## 🚀 Quick Start

### Basic Printing

```dart
import 'package:niim_blue_flutter/niim_blue_flutter.dart';

// 1. Connect to printer
final client = NiimbotBluetoothClient();
await client.connect(); // Auto-scans and connects to first NIIMBOT device

// 2. Create print task (auto-detects printer model)
client.stopHeartbeat();
client.setPacketInterval(0); // Fast printing
final task = client.createPrintTask(PrintOptions(
  totalPages: 1,
  density: 3,
  labelType: 1,
));

if (task == null) {
  throw Exception('Printer model not detected');
}

// 3. Build page content
final page = PrintPage(400, 240); // width x height in pixels

page.addText('Hello NIIMBOT!', TextOptions(
  x: 192,
  y: 100,
  fontSize: 24,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
));

// 4. Print
await task.printInit();
await task.printPage(page.toEncodedImage(), 1);
await task.waitForFinished();
client.startHeartbeat();
```

## 📖 Usage Examples

### Page Orientation

Use `orientation` parameter to automatically rotate all content for landscape printing:

```dart
// Portrait mode (default) - for vertical labels
final portraitPage = PrintPage(400, 240, orientation: PageOrientation.portrait);
portraitPage.addText('Product Name', TextOptions(x: 200, y: 120));

// Landscape mode - for horizontal labels on vertical paper
// Dimensions are AUTO-SWAPPED: 240x400 becomes 400x240 canvas + 90° rotation
final landscapePage = PrintPage(240, 400, orientation: PageOrientation.landscape);
landscapePage.addText('Product Name', TextOptions(
  x: 200, // Same coordinates work!
  y: 120, // Canvas is 400x240 (swapped) + rotated 90°
));
```

**How it works:**
- Physical paper: 240px width × 400px height (vertical)
- `PrintPage(240, 400, orientation: PageOrientation.landscape)`:
  - ✅ Canvas dimensions: **400×240** (auto-swapped)
  - ✅ Content rotated: **90°** clockwise
  - ✅ Result: Horizontal content on vertical paper
  - ✅ Same coordinates as `PrintPage(400, 240, orientation: PageOrientation.portrait)`

### Text Rendering

```dart
final page = PrintPage(400, 240);

// Simple text with default font
page.addText('NIIMBOT PRINTER', TextOptions(
  x: 192,
  y: 50,
  fontSize: 24,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
));

// Bold text with rotation
page.addText('Rotated Text', TextOptions(
  x: 192,
  y: 100,
  fontSize: 20,
  fontWeight: FontWeight.bold,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  rotate: 45, // Additional rotation (on top of page orientation)
));

// Custom font
page.addText('Custom Font Text', TextOptions(
  x: 100,
  y: 180,
  fontSize: 16,
  fontFamily: 'Roboto',
  align: HAlignment.left,
));
```

### QR Code

```dart
page.addQR('https://github.com', QROptions(
  x: 192,
  y: 100,
  width: 150,
  height: 150,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  ecl: QRErrorCorrectLevel.M, // L, M, Q, H
  rotate: 90, // Optional: rotate 90 degrees
));
```

### Barcode

```dart
page.addBarcode('123456789012', BarcodeOptions(
  encoding: BarcodeEncoding.ean13, // or code128
  x: 192,
  y: 150,
  width: 200,
  height: 60,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  rotate: 180, // Optional: rotate 180 degrees
));
```

### Image from File

```dart
import 'dart:io';
import 'package:image/image.dart' as img;

final imageBytes = await File('path/to/image.jpg').readAsBytes();
final image = img.decodeImage(imageBytes)!;

page.addImageFromBuffer(ImageFromBufferOptions(
  buffer: image,
  x: 192,
  y: 100,
  width: 200,
  height: 150,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  threshold: 128, // Grayscale to binary threshold
  rotate: 270, // Optional: rotate 270 degrees
));
```

### Image from Network

```dart
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

final response = await http.get(Uri.parse('https://example.com/logo.png'));
final image = img.decodeImage(response.bodyBytes)!;

page.addImageFromBuffer(ImageFromBufferOptions(
  buffer: image,
  x: 192,
  y: 100,
  width: 150,
  height: 150,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  threshold: 128,
));
```

### Custom Pixel Data

```dart
final heartPixels = [
  0,0,0,0,1,1,0,0,0,0,1,1,0,0,0,0,
  0,0,1,1,1,1,1,0,0,1,1,1,1,0,0,0,
  0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
  // ... (1 = black, 0 = white)
];

page.addPixelData(ImageOptions(
  data: heartPixels,
  imageWidth: 16,
  imageHeight: 11,
  x: 192,
  y: 100,
  width: 128, // Scaled width
  height: 88,
  align: HAlignment.center,
  vAlign: VAlignment.middle,
  rotate: 45, // Optional: rotate 45 degrees
));
```

### Line Drawing

```dart
page.addLine(LineOptions(
  x: 10,
  y: 100,
  endX: 374,
  endY: 100,
  thickness: 2,
));
```

### Print Preview

```dart
final page = PrintPage(400, 240);
page.addQR('Preview Test', QROptions(
  x: 192, 
  y: 100, 
  align: HAlignment.center, 
  vAlign: VAlignment.middle,
));

// Generate PNG bytes
final pngBytes = await page.toPreviewImage();
// Display in Image.memory(pngBytes)
```

## 🔧 API Reference

### NiimbotBluetoothClient

#### Methods

- `connect({String? deviceId})`: Connect to printer (auto-scan or specific device)
- `disconnect()`: Disconnect from printer
- `setOnDisconnect(void Function() callback)`: Set callback for disconnect events
- `listDevices({Duration? timeout})`: List available printers
- `listConnectedDevices()`: List already connected printers
- `createPrintTask(PrintOptions? options)`: Create print task with auto-detection
- `setPacketInterval(int ms)`: Set delay between packets (0 = fastest)
- `startHeartbeat()` / `stopHeartbeat()`: Control heartbeat

### PrintPage

#### Constructor

```dart
PrintPage(int width, int height, {PageOrientation? orientation})
```

- `width: int` - Page width in pixels
- `height: int` - Page height in pixels
- `orientation: PageOrientation?` - Page orientation (default: portrait)
  - `PageOrientation.portrait`: Normal orientation, canvas dimensions = (width, height)
  - `PageOrientation.landscape`: **Auto-swaps dimensions** → canvas becomes (height, width) + rotates all content 90° clockwise
    - Perfect for printing horizontal content on vertical paper
    - Example: `PrintPage(240, 400, orientation: PageOrientation.landscape)` → 400×240 canvas with 90° rotation
    - Use same coordinates as `PrintPage(400, 240, orientation: PageOrientation.portrait)`

#### Methods

- `addText(String text, TextOptions options)`
- `addQR(String text, QROptions options)`
- `addBarcode(String text, BarcodeOptions options)`
- `addPixelData(ImageOptions options)`
- `addImageFromBuffer(ImageFromBufferOptions options)`
- `addImageFromUri(String uri, ImageFromBufferOptions options)`: Fetch and add image from URL
- `addLine(LineOptions options)`
- `toEncodedImage()`: Convert to printer format
- `toPreviewImage()`: Generate PNG bytes for preview

### Type Definitions

#### PrintOptions
- `totalPages: int?` - Number of pages to print
- `density: int?` - Print density (1-5, default: 3, higher = darker)
- `labelType: int?` - Label type identifier (printer-specific)
- `statusPollIntervalMs: int?` - Status polling interval in ms (default: 100)
- `statusTimeoutMs: int?` - Status check timeout in ms (default: 8000)

#### PrintElementOptions (Base)
All positioning options support:
- `x: double` - X coordinate in pixels
- `y: double` - Y coordinate in pixels
- `width: double?` - Optional width (auto-scales if only one dimension provided)
- `height: double?` - Optional height (auto-scales if only one dimension provided)
- `align: HAlignment?` - Horizontal alignment relative to x coordinate
  - `HAlignment.left`, `HAlignment.center`, `HAlignment.right`
- `vAlign: VAlignment?` - Vertical alignment relative to y coordinate
  - `VAlignment.top`, `VAlignment.middle`, `VAlignment.bottom`
- `rotate: double?` - Rotation angle in degrees (0-360), rotates around element center. This is additional rotation on top of page orientation.

#### TextOptions
Extends `PrintElementOptions` with:
- `fontSize: double?` - Font size in pixels (default: 12)
- `fontFamily: String?` - Font family name (optional, uses system font if not provided)
- `fontWeight: FontWeight?` - Font weight (optional, uses normal if not provided)

#### QROptions
Extends `PrintElementOptions` with:
- `ecl: QRErrorCorrectLevel?` - Error correction level (default: M)
  - `QRErrorCorrectLevel.L`: Low (~7% correction)
  - `QRErrorCorrectLevel.M`: Medium (~15% correction)
  - `QRErrorCorrectLevel.Q`: Quartile (~25% correction)
  - `QRErrorCorrectLevel.H`: High (~30% correction)

#### BarcodeOptions
Extends `PrintElementOptions` with:
- `encoding: BarcodeEncoding?` - Barcode encoding format (default: ean13)
  - `BarcodeEncoding.ean13`
  - `BarcodeEncoding.code128`

#### ImageOptions
Extends `PrintElementOptions` with:
- `data: List<int>` - 1D array of pixel data (1 = black, 0 = white)
- `imageWidth: int` - Original image width in pixels
- `imageHeight: int` - Original image height in pixels

#### ImageFromBufferOptions
Extends `PrintElementOptions` with:
- `buffer: img.Image` - Image from package:image
- `threshold: int?` - Grayscale to binary conversion threshold (0-255, default: 128, lower = darker)
- Plus all `PrintElementOptions` (x, y, width, height, align, vAlign, rotate)

#### LineOptions
- `x: double` - Start X coordinate in pixels
- `y: double` - Start Y coordinate in pixels
- `endX: double` - End X coordinate in pixels
- `endY: double` - End Y coordinate in pixels
- `thickness: double?` - Line thickness in pixels (default: 1)

## 🎯 Alignment System

The library uses **reference point alignment**:

```dart
// Center text at position (192, 100)
page.addText('Centered', TextOptions(
  x: 192,    // Reference X
  y: 100,    // Reference Y
  align: HAlignment.center,   // Text center aligns to x
  vAlign: VAlignment.middle,  // Text middle aligns to y
));

// Right-bottom align at position (350, 180)
page.addText('Corner', TextOptions(
  x: 350,
  y: 180,
  align: HAlignment.right,   // Right edge at x=350
  vAlign: VAlignment.bottom, // Bottom edge at y=180
));
```

## 🐛 Troubleshooting

### Bluetooth Connection Issues
- **Problem**: Cannot find or connect to printer
- **Solution**: 
  - Ensure Bluetooth is enabled on your device
  - Make sure printer is powered on and in pairing mode
  - Check that all required permissions are granted (Bluetooth, Location on Android)
  - Try `listDevices()` to scan for available printers

### Print Quality Issues
- **Problem**: Print is too light or too dark
- **Solution**: Adjust the `density` parameter (1-5, default 3) in `createPrintTask()`

### Image Not Printing Correctly
- **Problem**: Image appears distorted or incorrect colors
- **Solution**: 
  - Ensure image dimensions are multiples of 8 pixels for width
  - Adjust `threshold` parameter (default 128) in `addImageFromBuffer()`
  - Images are converted to black & white - use high contrast images

### Permission Issues on Android
- **Problem**: Bluetooth permissions error
- **Solution**:
  - Android 12+ requires different permissions - handled automatically
  - Make sure all permissions are declared in AndroidManifest.xml
  - Request runtime permissions using `permission_handler` package

### Build Errors
- **Problem**: Native module errors during build
- **Solution**:
  - Run `pod install` in iOS directory: `cd ios && pod install`
  - For Android, sync gradle after adding dependencies
  - Clean build: `flutter clean && flutter pub get`

## 📄 License

MIT

## 🙏 Credits

Based on [niimbluelib](https://github.com/MultiMote/niimblue) by MultiMote.
