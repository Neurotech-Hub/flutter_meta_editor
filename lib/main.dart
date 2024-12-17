import 'package:flutter/material.dart';
import 'dart:convert';
import 'widgets/json_form_field.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'screens/ble_scan_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadInitialJson();
  }

  Future<void> _loadInitialJson() async {
    try {
      final jsonString =
          await DefaultAssetBundle.of(context).loadString('assets/meta.json');
      _parseJson(jsonString);
    } catch (e) {
      setState(() {
        _jsonError = 'Error loading meta.json: $e';
      });
    }
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
          centerTitle: false,
          title: Text(
            'meta.json Editor',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                ),
          ),
          actions: [
            TextButton.icon(
              icon: Icon(
                Icons.bluetooth,
                color: _connectedDevice != null ? Colors.blue : Colors.grey,
              ),
              label: Text(_connectedDevice?.name ?? 'Not Connected'),
              onPressed: () async {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BLEScanScreen(),
                  ),
                );
                
                if (result != null) {
                  final device = result['device'] as BLEDevice;
                  final jsonData = result['json'] as String;
                  
                  setState(() {
                    _connectedDevice = device;
                    _parseJson(jsonData);
                  });
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
}
