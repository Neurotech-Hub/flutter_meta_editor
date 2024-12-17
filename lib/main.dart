import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'widgets/json_form_field.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'screens/ble_scan_screen.dart';
import 'services/ble_file_transfer.dart';

Future<void> checkBluetoothState() async {
  // Check adapter availability
  if (await FlutterBluePlus.isAvailable == false) {
    throw Exception('Bluetooth is not available on this device');
  }

  // Turn on Bluetooth if it's not already on
  if (await FlutterBluePlus.isOn == false) {
    throw Exception('Please turn on Bluetooth to use this feature');
  }
}

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        fontFamily: 'Outfit',
      ),
      home: const JsonEditorScreen(),
    );
  }
}

class JsonEditorScreen extends StatefulWidget {
  const JsonEditorScreen({super.key});

  @override
  State<JsonEditorScreen> createState() => _JsonEditorScreenState();
}

class _JsonEditorScreenState extends State<JsonEditorScreen> {
  Map<String, dynamic>? _jsonData;
  String? _jsonError;
  BLEDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  final List<BLEDevice> _scanResults = [];
  final _formKey = GlobalKey<JsonFormFieldState>();

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      await FlutterBluePlus.stopScan();

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
              _scanResults
                ..clear()
                ..addAll(validDevices);
            });
          }
        },
      );

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );

      setState(() {
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan error: $e')),
      );
    }
  }

  void _handleDisconnect() {
    setState(() {
      _connectedDevice = null;
      _jsonData = null;
      _jsonError = null;
      _scanResults.clear();
    });
  }

  void _setupConnectionListener(BLEDevice device) {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = device.device.connectionState.listen(
      (BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device disconnected'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  Widget _buildBody() {
    if (_connectedDevice == null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.bluetooth_searching,
                      color: Color(0xFF2196F3),
                    ),
              label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
              onPressed: _isScanning ? null : _startScan,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemBuilder: (BuildContext context, int index) {
                final device = _scanResults[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: device.isConnected
                          ? const Color(0xFF2196F3)
                          : const Color(0xFF757575),
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
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF2196F3),
                              ),
                            ),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
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
      );
    }

    return TabBarView(
      children: [
        _buildFormView(),
        _buildRawEditor(),
        _buildPrettyView(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          elevation: 0,
          title: const Text(
            'Hublink Editor',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 22,
            ),
          ),
          actions: _connectedDevice != null
              ? [
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.sync_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Sync',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF2196F3),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () async {
                      if (_jsonData == null) return;

                      // Commit any pending changes
                      _commitFormChanges();

                      final fileTransfer = BleFileTransfer();
                      final jsonString = const JsonEncoder().convert(_jsonData);

                      try {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Text('Syncing meta.json...'),
                              ],
                            ),
                            duration: Duration(seconds: 60),
                          ),
                        );

                        await fileTransfer.syncMetaJson(
                          _connectedDevice!.device,
                          jsonString,
                        );

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 16),
                                Text('Sync completed successfully'),
                              ],
                            ),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.error, color: Colors.white),
                                const SizedBox(width: 16),
                                Expanded(child: Text('Sync error: $e')),
                              ],
                            ),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.bluetooth_disabled,
                      size: 18,
                      color: Color(0xFF757575),
                    ),
                    label: const Text(
                      'Disconnect',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF757575),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () async {
                      await _connectedDevice?.device.disconnect();
                      _handleDisconnect();
                    },
                  ),
                  const SizedBox(width: 20),
                ]
              : null,
          bottom: _connectedDevice != null
              ? TabBar(
                  indicatorColor: const Color(0xFF2196F3),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w500,
                  ),
                  unselectedLabelColor: const Color(0xFF757575),
                  labelColor: const Color(0xFF2196F3),
                  tabs: const [
                    Tab(icon: Icon(Icons.view_list), text: 'Form View'),
                    Tab(icon: Icon(Icons.code), text: 'Raw Editor'),
                    Tab(icon: Icon(Icons.preview), text: 'Pretty View'),
                  ],
                )
              : null,
        ),
        body: _buildBody(),
      ),
    );
  }

  void _parseJson(String jsonString) {
    try {
      final parsed = json.decode(jsonString);
      setState(() {
        _jsonData = parsed;
        _jsonError = null;
      });
    } catch (e) {
      setState(() {
        _jsonError = e.toString();
      });
    }
  }

  Widget _buildFormView() {
    if (_jsonError != null) {
      return Center(child: Text('Error: $_jsonError'));
    }
    if (_jsonData == null) {
      return const Center(child: Text('No valid JSON data'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: JsonFormField(
        key: _formKey,
        fieldName: 'root',
        value: _jsonData,
        isRoot: true,
        onChanged: (newValue) {
          setState(() {
            _jsonData = newValue as Map<String, dynamic>;
          });
        },
      ),
    );
  }

  Widget _buildRawEditor() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        maxLines: null,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Enter JSON here',
        ),
        controller: TextEditingController(
            text: _jsonData != null
                ? const JsonEncoder.withIndent('  ').convert(_jsonData)
                : ''),
        onChanged: _parseJson,
      ),
    );
  }

  Widget _buildPrettyView() {
    if (_jsonError != null) {
      return Center(child: Text('Error: $_jsonError'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: _jsonData != null
          ? HighlightView(
              const JsonEncoder.withIndent('  ').convert(_jsonData),
              language: 'json',
              theme: githubTheme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            )
          : const Text('No valid JSON data'),
    );
  }

  Future<void> _connectToDevice(BLEDevice bleDevice) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 16),
            Text('Connecting...'),
          ],
        ),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      await checkBluetoothState();
      await bleDevice.device.connect();
      final fileTransfer = BleFileTransfer();

      await fileTransfer.writeGatewayData(bleDevice.device);

      // Read initial meta.json
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 16),
              Text('Reading meta.json...'),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      final jsonData = await fileTransfer.readMetaJson(bleDevice.device);
      print('Received meta.json data: $jsonData'); // Debug log

      if (!mounted) return;

      // Show success and update UI
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

      setState(() {
        _connectedDevice = bleDevice;
        print('Parsing JSON data...'); // Debug log
        _parseJson(jsonData); // Parse and display the received meta.json
      });

      _setupConnectionListener(bleDevice);
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

  void _commitFormChanges() {
    _formKey.currentState?.commitChanges();
  }

  void _handleSync() async {
    if (_jsonData == null) return;

    _commitFormChanges(); // Commit any pending changes

    final fileTransfer = BleFileTransfer();
    final jsonString = const JsonEncoder().convert(_jsonData);
    // ... rest of sync code
  }
}
