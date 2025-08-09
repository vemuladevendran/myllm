import 'package:flutter/material.dart';
import '../models/model_metadata.dart';

class InputBar extends StatefulWidget {
  final Function(String, ModelMetadata) onSend;
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
  ModelMetadata? _selectedModel;

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a downloaded model first."),
        ),
      );
      return;
    }

    widget.onSend(text, _selectedModel!);
    _controller.clear();
  }

  @override
  void initState() {
    super.initState();
    if (widget.downloadedModels.isNotEmpty) {
      _selectedModel = widget.downloadedModels.first;
    }
  }

  @override
  void didUpdateWidget(covariant InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the list changed and current selection is no longer valid, reselect
    if (_selectedModel == null && widget.downloadedModels.isNotEmpty) {
      setState(() => _selectedModel = widget.downloadedModels.first);
    } else if (_selectedModel != null &&
        !widget.downloadedModels.contains(_selectedModel)) {
      setState(() {
        _selectedModel = widget.downloadedModels.isNotEmpty
            ? widget.downloadedModels.first
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModels = widget.downloadedModels.isNotEmpty;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).cardColor,
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            DropdownButton<ModelMetadata>(
              value: _selectedModel,
              hint: const Text("Select model"),
              items: widget.downloadedModels.map((model) {
                return DropdownMenuItem(value: model, child: Text(model.name));
              }).toList(),
              onChanged: hasModels
                  ? (value) {
                      setState(() => _selectedModel = value);
                    }
                  : null,
              underline: const SizedBox.shrink(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: hasModels
                      ? "Enter your prompt..."
                      : "Download a model first (Models tab)",
                  border: InputBorder.none,
                  isDense: true,
                ),
                enabled: hasModels,
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: hasModels ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
