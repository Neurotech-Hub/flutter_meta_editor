import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleFileTransfer {
  static const String SERVICE_UUID = "57617368-5501-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILENAME =
      "57617368-5502-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILETRANSFER =
      "57617368-5503-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_GATEWAY =
      "57617368-5504-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_NODE =
      "57617368-5505-0001-8000-00805f9b34fb";
  static const int CHUNK_TIMEOUT = 5; // seconds
  static const int MAX_RETRIES = 3;
  bool _isSyncing = false;

  BleFileTransfer() {
    // Remove or modify logging level
    FlutterBluePlus.setLogLevel(LogLevel.none);  // Or LogLevel.error for critical issues only
  }

  Map<String, dynamic> _createGatewayPayload() {
    // Get current timestamp in seconds (Unix timestamp)
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).floor();

    return {
      'timestamp': timestamp,
      'watchdogTimeoutMs': 120000,
    };
  }

  Future<void> writeGatewayData(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Required BLE service not found'),
      );

      final characteristic = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() ==
            CHARACTERISTIC_UUID_GATEWAY.toLowerCase(),
        orElse: () => throw Exception('Gateway characteristic not found'),
      );

      final payload = _createGatewayPayload();
      final jsonString = jsonEncode(payload);

      await characteristic.write(
        utf8.encode(jsonString),
        withoutResponse: false,
      );
    } catch (e) {
      throw Exception('Failed to write gateway data: $e');
    }
  }

  Future<void> _enableIndications(
      BluetoothCharacteristic characteristic) async {
    // Check if characteristic supports indications
    if (!characteristic.properties.indicate) {
      throw Exception('Characteristic does not support indications');
    }

    await characteristic.setNotifyValue(true);

    // Verify indication is enabled
    final isEnabled = await characteristic.isNotifying;
    if (!isEnabled) {
      throw Exception(
          'Failed to enable indications on characteristic: ${characteristic.uuid}');
    }

    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<String> readMetaJson(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Required BLE service not found'),
      );

      // Get both required characteristics
      final filenameChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == 
              CHARACTERISTIC_UUID_FILENAME.toLowerCase(),
        orElse: () => throw Exception('Filename characteristic not found'),
      );

      final transferChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == 
              CHARACTERISTIC_UUID_FILETRANSFER.toLowerCase(),
        orElse: () => throw Exception('File transfer characteristic not found'),
      );

      await _enableIndications(transferChar);

      final completer = Completer<String>();
      List<int> fileData = [];

      final subscription = transferChar.onValueReceived.listen(
        (value) {
          if (value.length == 3 && String.fromCharCodes(value) == 'EOF') {
            try {
              final jsonStr = utf8.decode(fileData);
              json.decode(jsonStr); // Verify JSON is valid
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

      try {
        await filenameChar.write(utf8.encode('meta.json'));
        return await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('File transfer timed out'),
        );
      } finally {
        subscription.cancel();
        await transferChar.setNotifyValue(false);
      }
    } catch (e) {
      throw Exception('Failed to read meta.json: $e');
    }
  }

  Future<void> syncMetaJson(BluetoothDevice device, String jsonData) async {
    if (_isSyncing) {
      throw Exception('Sync already in progress');
    }

    try {
      _isSyncing = true;

      try {
        await device.requestMtu(512);
      } catch (e) {
        print('MTU negotiation failed: $e');
      }

      final mtu = await device.mtu.first;
      final chunkSize = mtu - 3;

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Required BLE service not found'),
      );

      final gatewayChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() ==
            CHARACTERISTIC_UUID_GATEWAY.toLowerCase(),
        orElse: () => throw Exception('Gateway characteristic not found'),
      );

      final chunks = _splitIntoChunks(jsonData, chunkSize);
      print('Syncing meta.json...');

      var chunkId = 1;
      for (final chunk in chunks) {
        final payload = {
          'metaJsonId': chunkId,
          'metaJsonData': chunk,
        };
        await gatewayChar.write(
          utf8.encode(jsonEncode(payload)),
          withoutResponse: false,
        );
        await Future.delayed(const Duration(milliseconds: 100));
        chunkId++;
      }

      final eofPayload = {
        'metaJsonId': 0,
        'metaJsonData': 'EOF',
      };
      await gatewayChar.write(
        utf8.encode(jsonEncode(eofPayload)),
        withoutResponse: false,
      );
      await Future.delayed(const Duration(milliseconds: 100));
      print('Sync complete');

    } finally {
      _isSyncing = false;
    }
  }

  List<String> _splitIntoChunks(String data, int chunkSize) {
    final chunks = <String>[];
    for (var i = 0; i < data.length; i += chunkSize) {
      chunks.add(
        data.substring(
            i, i + chunkSize > data.length ? data.length : i + chunkSize),
      );
    }
    return chunks;
  }
}
