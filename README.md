# Label Printer

A small Android app for printing labels on a **NIIMBOT D110_M** label printer over Bluetooth.

This is an early **test app**. It has one screen:

1. **Connect to printer**: finds the D110 and connects.
2. **Label text**: type what you want printed.
3. **Print**: prints it on a 40 × 12 mm label.

Status messages appear at the bottom so problems are easy to screenshot.

## Getting the app

GitHub builds the app automatically. To install it on your phone:

1. Open this repository on GitHub and tap **Releases**.
2. Open the newest **Label Printer test build**.
3. Tap **label-printer.apk** to download it, then open it to install.

## Settings used

These match what worked in NiimBlue for the D110_M:

- Label: 40 × 12 mm, 203 dpi (320 × 96 dots)
- Print task: D110M_V4 (auto-detected)
- Density: 3
- Label type: With gaps

## Built with

- [Flutter](https://flutter.dev)
- [niim_blue_flutter](https://pub.dev/packages/niim_blue_flutter), a Flutter version of the [NiimBlue](https://github.com/MultiMote/niimblue) printing library

## Plan

The long-term goal is to say "Hey Claude, print a label that says Flour with today's date" and have it print with no tapping.
