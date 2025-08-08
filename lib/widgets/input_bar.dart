// lib/widgets/input_bar.dart
import 'package:flutter/material.dart';
import '../models/model_metadata.dart';

class InputBar extends StatefulWidget {
  final Function(String, String) onSend;
  final List<ModelMetadata> downloadedModels;

  const InputBar({
    super.key,
    required this.onSend,
    required this.downloadedModels,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedModel;

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && _selectedModel != null) {
      widget.onSend(text, _selectedModel!);
      _controller.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.downloadedModels.isNotEmpty) {
      _selectedModel = widget.downloadedModels.first.name;
    }
  }

  @override
  void didUpdateWidget(covariant InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedModel == null && widget.downloadedModels.isNotEmpty) {
      setState(() {
        _selectedModel = widget.downloadedModels.first.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            DropdownButton<String>(
              value: _selectedModel,
              items: widget.downloadedModels.map((model) {
                return DropdownMenuItem(
                  value: model.name,
                  child: Text(model.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedModel = value;
                });
              },
              underline: const SizedBox.shrink(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: "Enter a prompt...",
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
