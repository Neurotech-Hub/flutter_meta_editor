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
    setState(() {
      bleDevice.isConnected = true;
    });

    try {
      // Clear any existing SnackBars
      ScaffoldMessenger.of(context).clearSnackBars();

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Connecting to device...'),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      await bleDevice.device.connect(
        timeout: const Duration(seconds: 4),
      );

      if (!mounted) return;

      // Update to writing gateway data
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Initializing connection...'),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      // Write gateway data before reading meta.json
      final fileTransfer = BleFileTransfer();
      await fileTransfer.writeGatewayData(bleDevice.device);

      if (!mounted) return;

      // Continue with reading meta.json...
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Reading meta.json...'),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      final jsonData = await fileTransfer.readMetaJson(bleDevice.device);

      if (!mounted) return;

      // Show brief success message
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 16),
              Text('Connected successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );

      // Return both the device and the JSON data
      Navigator.pop(context, {
        'device': bleDevice,
        'json': jsonData,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        bleDevice.isConnected = false;
      });

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(child: Text('Connection error: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );

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
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: device.isConnected ? Colors.blue : Colors.grey,
                      size: 32,
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      'Signal: ${device.rssi} dBm',
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: device.isConnected
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => _connectToDevice(device),
                            child: const Text('Connect'),
                          ),
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
