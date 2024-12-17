import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JsonFormField extends StatefulWidget {
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
  State<JsonFormField> createState() => JsonFormFieldState();
}

class JsonFormFieldState extends State<JsonFormField> {
  late TextEditingController _controller;
  dynamic _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(
      text: widget.value is String || widget.value is int
          ? widget.value.toString()
          : null,
    );
  }

  void _handleTextChange(String value) {
    _currentValue = value; // Update current value without triggering onChange
  }

  void _handleSubmitted(String value) {
    widget.onChanged(value); // Only trigger onChange when submitted
  }

  // Add this method to commit pending changes
  void commitChanges() {
    if (_currentValue != widget.value) {
      widget.onChanged(_currentValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value == null) {
      return const Text('null');
    }

    if (widget.value is Map<String, dynamic>) {
      final optionsMap = <String, List<String>>{};
      final fieldsToHide = <String>[];

      // Collect all *_options fields
      for (final entry in widget.value.entries) {
        if (entry.key.endsWith('_options') && entry.value is List) {
          final baseFieldName = entry.key.replaceAll('_options', '');
          if (widget.value.containsKey(baseFieldName)) {
            optionsMap[baseFieldName] = List<String>.from(entry.value);
            fieldsToHide.add(entry.key);
          }
        }
      }

      // Shared function to build entry widgets
      List<Widget> buildEntryWidgets() {
        return widget.value.entries.map<Widget>((entry) {
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
                          final newMap =
                              Map<String, dynamic>.from(widget.value);
                          newMap[entry.key] = newValue;
                          widget.onChanged(newMap);
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
                final newMap = Map<String, dynamic>.from(widget.value);
                newMap[entry.key] = newValue;
                widget.onChanged(newMap);
              },
            ),
          );
        }).toList();
      }

      return widget.isRoot
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
                        widget.fieldName,
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

    if (widget.value is bool) {
      return _buildBoolField();
    } else if (widget.value is int) {
      return _buildIntField();
    } else if (widget.value is double) {
      return _buildDoubleField();
    } else if (widget.value is String) {
      return _buildStringField();
    }
    return Text('Unsupported type: ${widget.value.runtimeType}');
  }

  Widget _buildBoolField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Switch(
            value: widget.value as bool,
            onChanged: (bool newValue) {
              widget.onChanged(newValue);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIntField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(widget.fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: widget.fieldName,
                isDense: true,
              ),
              controller: _controller,
              onChanged: (String value) {
                _currentValue = value.isEmpty ? 0 : int.parse(value);
              },
              onSubmitted: (String value) {
                widget.onChanged(value.isEmpty ? 0 : int.parse(value));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoubleField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(widget.fieldName, style: const TextStyle(fontSize: 16)),
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
                labelText: widget.fieldName,
                isDense: true,
              ),
              controller: TextEditingController(text: widget.value.toString()),
              onChanged: (String newValue) {
                if (newValue.isNotEmpty) {
                  widget.onChanged(double.parse(newValue));
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
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(widget.fieldName, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: widget.fieldName,
                isDense: true,
              ),
              controller: _controller,
              onChanged: _handleTextChange,
              onSubmitted: _handleSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}
