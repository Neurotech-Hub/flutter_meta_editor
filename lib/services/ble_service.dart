import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  static const String SERVICE_UUID = "57617368-5501-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILENAME =
      "57617368-5502-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_FILETRANSFER =
      "57617368-5503-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_GATEWAY =
      "57617368-5504-0001-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID_NODE =
      "57617368-5505-0001-8000-00805f9b34fb";

  BluetoothDevice? _device;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _fileTransferSubscription;
  final _fileDataController = StreamController<List<int>>();

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect();

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          disconnect();
        }
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Verify required service and characteristics exist
      final targetService = services.firstWhere(
        (service) => service.uuid.toString() == SERVICE_UUID,
        orElse: () => throw Exception('Required BLE service not found'),
      );

      final hasRequiredCharacteristics = targetService.characteristics.any(
              (char) => char.uuid.toString() == CHARACTERISTIC_UUID_FILENAME) &&
          targetService.characteristics.any((char) =>
              char.uuid.toString() == CHARACTERISTIC_UUID_FILETRANSFER);

      if (!hasRequiredCharacteristics) {
        throw Exception('Required BLE characteristics not found');
      }

      return true;
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  Future<String> readMetaJson() async {
    if (_device == null) throw Exception('Device not connected');

    List<BluetoothService> services = await _device!.discoverServices();
    final service = services.firstWhere(
      (service) => service.uuid.toString() == SERVICE_UUID,
    );

    // Get characteristics
    final filenameChar = service.characteristics.firstWhere(
      (char) => char.uuid.toString() == CHARACTERISTIC_UUID_FILENAME,
    );
    final fileTransferChar = service.characteristics.firstWhere(
      (char) => char.uuid.toString() == CHARACTERISTIC_UUID_FILETRANSFER,
    );

    // Subscribe to file transfer notifications
    await fileTransferChar.setNotifyValue(true);
    _fileTransferSubscription =
        fileTransferChar.onValueReceived.listen((value) {
      _fileDataController.add(value);
    });

    // Write filename to trigger transfer
    await filenameChar.write(utf8.encode('meta.json'));

    // Collect file data
    List<int> fileData = [];
    await for (final chunk in _fileDataController.stream) {
      // Check for EOF
      if (chunk.length == 3 && String.fromCharCodes(chunk) == 'EOF') {
        break;
      }
      fileData.addAll(chunk);
    }

    // Cleanup
    await fileTransferChar.setNotifyValue(false);
    await _fileTransferSubscription?.cancel();
    _fileTransferSubscription = null;

    return utf8.decode(fileData);
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    await _fileTransferSubscription?.cancel();
    _connectionSubscription = null;
    _fileTransferSubscription = null;
    if (_device != null) {
      await _device!.disconnect();
      _device = null;
    }
  }

  void dispose() {
    _fileDataController.close();
    disconnect();
  }
}
