import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleFileTransfer {
  static const String SERVICE_UUID = "57617368-5501-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILENAME =
      "57617368-5502-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILETRANSFER =
      "57617368-5503-0001-8000-00805f9b34fb";

  Future<String> readMetaJson(BluetoothDevice device) async {
    try {
      // Discover services
      final services = await device.discoverServices();

      // Find our service
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Required BLE service not found'),
      );

      // Get required characteristics
      final filenameChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            CHARACTERISTIC_UUID_FILENAME.toLowerCase(),
        orElse: () => throw Exception('Filename characteristic not found'),
      );

      final transferChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            CHARACTERISTIC_UUID_FILETRANSFER.toLowerCase(),
        orElse: () => throw Exception('File transfer characteristic not found'),
      );

      // Create a completer to handle the async file transfer
      final completer = Completer<String>();
      List<int> fileData = [];

      // Subscribe to notifications
      await transferChar.setNotifyValue(true);
      final subscription = transferChar.onValueReceived.listen(
        (value) {
          // Check for EOF
          if (value.length == 3 && String.fromCharCodes(value) == 'EOF') {
            // Validate and complete
            try {
              final jsonStr = utf8.decode(fileData);
              // Verify it's valid JSON
              json.decode(jsonStr);
              completer.complete(jsonStr);
            } catch (e) {
              completer.completeError('Invalid JSON received: $e');
            }
          } else {
            fileData.addAll(value);
          }
        },
        onError: (error) {
          completer.completeError('File transfer error: $error');
        },
      );

      // Write filename to trigger transfer
      await filenameChar.write(utf8.encode('meta.json'));

      // Wait for completion or timeout
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          subscription.cancel();
          throw TimeoutException('File transfer timed out');
        },
      ).whenComplete(() {
        subscription.cancel();
        transferChar.setNotifyValue(false);
      });
    } catch (e) {
      throw Exception('File transfer failed: $e');
    }
  }
}
