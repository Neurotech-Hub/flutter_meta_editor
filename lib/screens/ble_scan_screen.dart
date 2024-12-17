import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../services/ble_file_transfer.dart';

class BLEDevice {
  final BluetoothDevice device;
  final int rssi;
  bool isConnected;

  BLEDevice({
    required this.device,
    required this.rssi,
    this.isConnected = false,
  });

  String get name => device.platformName;
  String get id => device.remoteId.str;
}

class BLEScanScreen extends StatefulWidget {
  const BLEScanScreen({super.key});

  @override
  State<BLEScanScreen> createState() => _BLEScanScreenState();
}

class _BLEScanScreenState extends State<BLEScanScreen> {
  bool _isInitialized = false;
  final List<BLEDevice> _devices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBle();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _restartBle() async {
    setState(() {
      _isInitialized = false;
      _devices.clear();
    });

    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan during restart: $e');
    }

    await _initBle();
  }

  Future<void> _initBle() async {
    try {
      // Check if Bluetooth is supported
      if (!await FlutterBluePlus.isSupported) {
        _showError('Bluetooth is not supported on this device');
        return;
      }

      // Request permissions first
      await _requestPermissions();

      // Wait for the adapter state to be ready
      final adapterState = await FlutterBluePlus.adapterState.first;

      // Set initial state
      if (mounted) {
        setState(() {
          _isInitialized = adapterState == BluetoothAdapterState.on;
        });
      }

      // Listen to adapter state changes
      _adapterStateSubscription?.cancel(); // Cancel any existing subscription
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (mounted) {
          final isOn = state == BluetoothAdapterState.on;
          setState(() => _isInitialized = isOn);

          if (isOn) {
            _startScan();
          } else {
            _showError('Bluetooth is turned off');
          }
        }
      });

      // If Bluetooth is off, try to turn it on
      if (adapterState == BluetoothAdapterState.off) {
        try {
          await FlutterBluePlus.turnOn().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('Bluetooth turn on timeout');
            },
          );
        } catch (e) {
          _showError('Failed to turn on Bluetooth: $e');
        }
      } else if (adapterState == BluetoothAdapterState.on) {
        // If Bluetooth is already on, start scanning
        await _startScan();
      }
    } catch (e) {
      _showError('Error initializing Bluetooth: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (!mounted) return;

    if (Theme.of(context).platform == TargetPlatform.android) {
      // Android permissions
      final statuses = await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (statuses.values.any((status) => !status.isGranted)) {
        _showError('Required permissions were not granted');
        return;
      }
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      // For iOS, we don't need to explicitly request bluetooth permission
      // The system will automatically prompt when needed
      return;
    }

    // Wait a bit for the system dialog to complete
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _startScan() async {
    if (!_isInitialized) {
      _showError('Bluetooth is not initialized');
      return;
    }

    setState(() {
      _devices.clear();
    });

    try {
      // Stop any existing scan
      await FlutterBluePlus.stopScan();

      // Start new scan
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          final validDevices = results
              .where((r) => r.device.platformName.isNotEmpty)
              .map((r) => BLEDevice(
                    device: r.device,
                    rssi: r.rssi,
                    isConnected: false,
                  ))
              .toList();

          validDevices.sort((a, b) => b.rssi.compareTo(a.rssi));

          if (mounted) {
            setState(() {
              _devices
                ..clear()
                ..addAll(validDevices);
            });
          }
        },
        onError: (e) {
          _showError('Scan error: $e');
        },
      );

      // Start scan with 10 second timeout
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      _showError('Error starting scan: $e');
    }
  }

  Future<void> _connectToDevice(BLEDevice bleDevice) async {
    try {
      await bleDevice.device.connect(
        timeout: const Duration(seconds: 4),
      );

      // Attempt to read meta.json
      final fileTransfer = BleFileTransfer();
      final jsonData = await fileTransfer.readMetaJson(bleDevice.device);

      if (!mounted) return;
      setState(() {
        bleDevice.isConnected = true;
      });

      // Return both the device and the JSON data
      Navigator.pop(context, {
        'device': bleDevice,
        'json': jsonData,
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Connection error: $e');
      try {
        await bleDevice.device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _disconnectDevice(BLEDevice bleDevice) async {
    try {
      await bleDevice.device.disconnect();
      if (!mounted) return;
      setState(() {
        bleDevice.isConnected = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Disconnection error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Device'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isInitialized)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Bluetooth is not initialized. Please check your Bluetooth settings.',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return ListTile(
                  leading: Icon(
                    Icons.bluetooth,
                    color: device.isConnected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(device.name),
                  subtitle: Text('${device.id}\nSignal: ${device.rssi} dBm'),
                  trailing: device.isConnected
                      ? TextButton(
                          onPressed: () => _disconnectDevice(device),
                          child: const Text('Disconnect'),
                        )
                      : TextButton(
                          onPressed: () => _connectToDevice(device),
                          child: const Text('Connect'),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
