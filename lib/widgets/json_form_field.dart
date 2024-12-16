import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JsonFormField extends StatelessWidget {
  final String fieldName;
  final dynamic value;
  final Function(dynamic) onChanged;
  final bool isRoot;

  const JsonFormField({
    super.key,
    required this.fieldName,
    required this.value,
    required this.onChanged,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      return _buildMapField(context);
    } else if (value is bool) {
      return _buildBoolField();
    } else if (value is int) {
      return _buildIntField();
    } else if (value is double) {
      return _buildDoubleField();
    } else if (value is String) {
      return _buildStringField();
    }
    return Text('Unsupported type: ${value.runtimeType}');
  }

  Widget _buildMapField(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isRoot)
              Text(
                fieldName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            const SizedBox(height: 8),
            ...((value as Map).entries.map((entry) {
              return JsonFormField(
                fieldName: entry.key,
                value: entry.value,
                onChanged: (newValue) {
                  final newMap = Map<String, dynamic>.from(value as Map);
                  newMap[entry.key] = newValue;
                  onChanged(newMap);
                },
              );
            })),
          ],
        ),
      ),
    );
  }

  Widget _buildBoolField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Switch(
            value: value as bool,
            onChanged: (bool newValue) {
              onChanged(newValue);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIntField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: fieldName,
                isDense: true,
              ),
              controller: TextEditingController(text: value.toString()),
              onChanged: (String newValue) {
                if (newValue.isNotEmpty) {
                  onChanged(int.parse(newValue));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoubleField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: fieldName,
                isDense: true,
              ),
              controller: TextEditingController(text: value.toString()),
              onChanged: (String newValue) {
                if (newValue.isNotEmpty) {
                  onChanged(double.parse(newValue));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStringField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: fieldName,
                isDense: true,
              ),
              controller: TextEditingController(text: value.toString()),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
