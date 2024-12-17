import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JsonFormField extends StatelessWidget {
  final String fieldName;
  final dynamic value;
  final bool isRoot;
  final Function(dynamic) onChanged;

  const JsonFormField({
    super.key,
    required this.fieldName,
    required this.value,
    this.isRoot = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text('null');
    }

    if (value is Map<String, dynamic>) {
      final optionsMap = <String, List<String>>{};
      final fieldsToHide = <String>[];

      // Collect all *_options fields
      for (final entry in value.entries) {
        if (entry.key.endsWith('_options') && entry.value is List) {
          final baseFieldName = entry.key.replaceAll('_options', '');
          if (value.containsKey(baseFieldName)) {
            optionsMap[baseFieldName] = List<String>.from(entry.value);
            fieldsToHide.add(entry.key);
          }
        }
      }

      // Shared function to build entry widgets
      List<Widget> buildEntryWidgets() {
        return value.entries.map<Widget>((entry) {
          if (fieldsToHide.contains(entry.key)) {
            return const SizedBox.shrink();
          }

          if (optionsMap.containsKey(entry.key)) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Text(entry.key),
                  ),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: entry.value.toString(),
                      items: optionsMap[entry.key]!.map((option) {
                        return DropdownMenuItem(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          final newMap = Map<String, dynamic>.from(value);
                          newMap[entry.key] = newValue;
                          onChanged(newMap);
                        }
                      },
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: entry.key,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: JsonFormField(
              fieldName: entry.key,
              value: entry.value,
              onChanged: (newValue) {
                final newMap = Map<String, dynamic>.from(value);
                newMap[entry.key] = newValue;
                onChanged(newMap);
              },
            ),
          );
        }).toList();
      }

      return isRoot
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buildEntryWidgets(),
            )
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        fieldName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...buildEntryWidgets(),
                  ],
                ),
              ),
            );
    }

    if (value is bool) {
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
