# Local changes to niim_blue_flutter

Copied from https://github.com/kidwar/flutter-niimblue-lib
(commit fe1bd930473c25db0685fdcdf31d4c0f08a96dfc, version 1.0.1, MIT license).

Changes:

1. `lib/src/client/abstract_client.dart` (`sendPacketWaitResponse`):
   start listening for the reply **before** sending the packet. The D110_M
   answers so quickly that the reply arrived before the listener was
   attached, causing "Timeout waiting response" errors.
2. `lib/src/client/bluetooth_client.dart`: listen with `onValueReceived`
   instead of `lastValueStream`, so our own writes are not echoed back as
   if they were printer replies.
3. `pubspec.yaml`: removed `dev_dependencies` (not needed to build the app).
