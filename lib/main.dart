import 'package:flutter/material.dart';
import 'dart:convert';
import 'widgets/json_form_field.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'screens/ble_scan_screen.dart';
import 'services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
  final String initialJson = '''{
    "hublink": {
      "advertise": "CUSTOM_NAME",
      "advertise_every": 300,
      "advertise_for": 30,
      "disable": false
    },
    "subject": {
      "id": "mouse001",
      "strain": "C57BL/6",
      "sex": "male"
    },
    "fed": {
      "program": "Classic"
    }
  }''';

  Map<String, dynamic>? _jsonData;
  String? _jsonError;
  BLEDevice? _connectedDevice;
  final BLEService _bleService = BLEService();

  @override
  void initState() {
    super.initState();
    _parseJson(initialJson);
  }

  void _parseJson(String jsonString) {
    try {
      setState(() {
        _jsonData = json.decode(jsonString);
        _jsonError = null;
      });
    } catch (e) {
      setState(() {
        _jsonError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('JSON Editor'),
          actions: [
            TextButton.icon(
              icon: Icon(
                Icons.bluetooth,
                color: _connectedDevice != null ? Colors.blue : Colors.grey,
              ),
              label: Text(_connectedDevice?.name ?? 'Not Connected'),
              onPressed: () async {
                final device = await Navigator.push<BLEDevice>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BLEScanScreen(),
                  ),
                );
                if (device != null) {
                  try {
                    await _bleService.connectToDevice(device.device);
                    final metaJson = await _bleService.readMetaJson();

                    setState(() {
                      _connectedDevice = device;
                      _parseJson(metaJson);
                    });
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Connection failed: ${e.toString()}')),
                    );
                    await _bleService.disconnect();
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _connectedDevice == null
                  ? null // Disable sync when not connected
                  : () async {
                      try {
                        final metaJson = await _bleService.readMetaJson();
                        setState(() {
                          _parseJson(metaJson);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Meta file synced successfully')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Sync failed: ${e.toString()}')),
                        );
                      }
                    },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.view_list), text: 'Form View'),
              Tab(icon: Icon(Icons.code), text: 'Raw Editor'),
              Tab(icon: Icon(Icons.preview), text: 'Pretty View'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFormView(),
            _buildRawEditor(),
            _buildPrettyView(),
          ],
        ),
      ),
    );
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

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}
