import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/model_metadata.dart';
import '../services/model_downloader.dart';
import '../state/model_provider.dart';

class ModelTile extends StatefulWidget {
  final ModelMetadata model;

  const ModelTile({super.key, required this.model});

  @override
  State<ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<ModelTile> {
  late Stopwatch _stopwatch;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    const kb = 1024, mb = kb * 1024, gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
    return '$bytes B';
  }

  String _eta(int received, int total) {
    if (received <= 0 || _stopwatch.elapsed.inSeconds == 0) return '--';
    final speed = received / _stopwatch.elapsed.inSeconds;
    final remaining = (total - received) / (speed > 1 ? speed : 1);
    return '${remaining.toStringAsFixed(1)}s left';
  }

  void _startDownload() {
    context.read<DownloadManager>().downloadModel(
          modelId: widget.model.id,
          fileName: widget.model.name,       // DISPLAY name (may contain '/')
          downloadUrl: widget.model.downloadUrl,
        );
  }

  void _cancelDownload() {
    context.read<DownloadManager>().cancel(widget.model.id);
  }

  Future<void> _deleteModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Model"),
        content: const Text("Are you sure you want to delete this model?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (confirm ?? false) {
      await context.read<DownloadManager>().deleteModel(
            widget.model.name,   // DISPLAY name; downloader sanitizes
            modelId: widget.model.id,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;

    final task = context.watch<DownloadManager>().getTask(model.id);
    final isDownloading = task != null && !task.isDone;
    final progress = task?.progress ?? 0.0;
    final received = task?.received ?? 0;
    final total = task?.total ?? 0;

    final isDownloaded = context.select<ModelProvider, bool>(
      (p) => p.isModelDownloaded(model.id),
    );

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListTile(
        title: Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold)), // DISPLAY name
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.description),
            const SizedBox(height: 6),
            Text('${model.sizeMB.toStringAsFixed(0)} MB'),
            if (isDownloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 6),
              Text(
                '${_formatBytes(received)} / ${_formatBytes(total)} • ${_eta(received, total)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: isDownloaded
            ? IconButton(icon: const Icon(Icons.delete), onPressed: _deleteModel)
            : isDownloading
                ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelDownload)
                : IconButton(icon: const Icon(Icons.download), onPressed: _startDownload),
      ),
    );
  }
}
