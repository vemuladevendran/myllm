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

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes > mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes > kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
    return '$bytes B';
  }

  String _estimatedTimeLeft(int received, int total) {
    if (received == 0 || _stopwatch.elapsed.inSeconds == 0) return '--';
    double speed = received / _stopwatch.elapsed.inSeconds;
    double remaining = (total - received) / speed;
    return '${remaining.toStringAsFixed(1)}s left';
  }

  void _startDownload() {
    context.read<DownloadManager>().downloadModel(
          modelId: widget.model.id,
          fileName: widget.model.name.replaceAll(' ', '_'),
          downloadUrl: widget.model.downloadUrl,
        );
  }

  void _cancelDownload() {
    context.read<DownloadManager>().cancel(widget.model.id);
  }

  void _deleteModel() async {
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
      final fileName = widget.model.name.replaceAll(' ', '_');
      await DownloadManager().deleteModel(fileName);

      if (mounted) {
        final provider = context.read<ModelProvider>();
        provider.markUndownloaded(widget.model.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final task = context.watch<DownloadManager>().getTask(model.id);

    final isDownloading = task != null && !task.isDone;
    final progress = task?.progress ?? 0.0;
    final downloaded = task?.received ?? 0;
    final total = task?.total ?? 1;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListTile(
        title: Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.description),
            const SizedBox(height: 4),
            Text('${model.sizeMB.toStringAsFixed(0)} MB'),
            if (isDownloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatBytes(downloaded)} / ${_formatBytes(total)} — ${_estimatedTimeLeft(downloaded, total)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: model.isDownloaded
            ? IconButton(icon: const Icon(Icons.delete), onPressed: _deleteModel)
            : isDownloading
                ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelDownload)
                : IconButton(icon: const Icon(Icons.download), onPressed: _startDownload),
      ),
    );
  }
}
