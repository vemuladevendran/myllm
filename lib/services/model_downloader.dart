import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../state/model_provider.dart';
import 'file_naming.dart'; // toGgufFileName

class DownloadTask {
  final String modelId;
  final String fileName;   // sanitized on-disk name WITH .gguf
  final String downloadUrl;

  int received = 0;
  int total = 1;
  bool isDone = false;
  bool isError = false;
  bool isCancelled = false;

  // internal
  IOSink? _sink;
  StreamSubscription<List<int>>? _subscription;

  DownloadTask({
    required this.modelId,
    required this.fileName,
    required this.downloadUrl,
  });

  double get progress => (total <= 0) ? 0.0 : (received / total).clamp(0.0, 1.0);

  Future<File> _destFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<int> _existingSize() async {
    final f = await _destFile();
    if (await f.exists()) {
      final len = await f.length();
      return len;
    }
    return 0;
  }

  Future<void> start({
    required VoidCallback onProgress,
    required VoidCallback onCompleteOrError,
    int maxRetries = 5,
  }) async {
    int attempt = 0;
    int written = await _existingSize(); // support resume
    received = written;

    // Try up to maxRetries with exponential backoff
    while (!isCancelled && attempt <= maxRetries) {
      final ok = await _tryOnce(
        onProgress: onProgress,
        onCompleteOrError: onCompleteOrError,
        resumeFrom: received,
        timeoutPerChunk: const Duration(seconds: 30),
      );

      if (ok) return; // completed

      attempt += 1;
      if (isCancelled) break;

      // backoff
      final delay = Duration(milliseconds: 500 * attempt * attempt);
      debugPrint('⏳ Retry $attempt/$maxRetries in ${delay.inMilliseconds}ms');
      await Future.delayed(delay);
    }

    // Failed after retries
    isError = !isCancelled && !isDone;
    onCompleteOrError();
  }

  Future<bool> _tryOnce({
    required VoidCallback onProgress,
    required VoidCallback onCompleteOrError,
    required int resumeFrom,
    required Duration timeoutPerChunk,
  }) async {
    http.Client? client;
    File? file;

    try {
      file = await _destFile();

      // If resumeFrom == 0, ensure fresh file
      if (resumeFrom == 0 && await file.exists()) {
        debugPrint('⚠️ Deleting old file before fresh start: ${file.path}');
        await file.delete();
      }

      _sink = file.openWrite(mode: FileMode.append);

      client = http.Client();
      final req = http.Request('GET', Uri.parse(downloadUrl))
        ..followRedirects = true
        ..persistentConnection = true
        ..headers.addAll({
          'User-Agent': 'myllm-android/1.0 (dart:http)',
          if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        });

      debugPrint('📥 Download start${resumeFrom > 0 ? " (resume from $resumeFrom)" : ""}: $modelId');
      debugPrint('⬇️ URL: $downloadUrl');
      debugPrint('📁 Path: ${file.path}');

      final res = await client.send(req);

      // Validate status
      final okStatuses = <int>{200, 206};
      if (!okStatuses.contains(res.statusCode)) {
        debugPrint('❌ HTTP ${res.statusCode} for $modelId');
        await _sink?.close();
        _sink = null;
        return false;
      }

      // Determine content length:
      //  - for 200 -> full size
      //  - for 206 -> content-length is remaining, total can be parsed from Content-Range
      final cl = res.contentLength ?? 0;
      if (res.statusCode == 200) {
        total = cl > 0 ? cl : 1;
      } else if (res.statusCode == 206) {
        total = _parseTotalFromContentRange(res.headers['content-range']) ?? (resumeFrom + cl);
      } else {
        total = (resumeFrom + cl);
      }

      // Consume stream (with timeout for each chunk)
      int lastProgressEmit = DateTime.now().millisecondsSinceEpoch;
      _subscription = res.stream.timeout(timeoutPerChunk).listen(
        (chunk) {
          if (isCancelled) return;
          received += chunk.length;
          _sink!.add(chunk);

          // throttle progress callbacks to ~60ms min interval to avoid jank
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastProgressEmit > 60) {
            onProgress();
            lastProgressEmit = now;
          }
        },
        onDone: () async {
          try {
            await _sink!.flush();
            await _sink!.close();
          } catch (_) {}
          _sink = null;

          // If we reached total (or we can't know the total but stream ended), mark done
          if (!isCancelled && (received >= total || total <= 1)) {
            isDone = true;
            debugPrint('✅ Download complete: ${file!.path}');
          }
          onCompleteOrError();
        },
        onError: (e) async {
          debugPrint('❌ Stream error: $e');
          try {
            await _sink?.close();
          } catch (_) {}
          _sink = null;
          // IMPORTANT: DO NOT DELETE the partial file -> we will resume next try
          onCompleteOrError();
        },
        cancelOnError: true,
      );

      // Wait for stream to finish or be cancelled
      await _subscription!.asFuture<void>().catchError((_) {});
      _subscription = null;

      return isDone; // true if finished this attempt
    } catch (e) {
      debugPrint('❌ Exception in attempt: $e');
      try {
        await _sink?.close();
      } catch (_) {}
      _sink = null;
      // keep partial file for resume
      return false;
    } finally {
      client?.close();
    }
  }

  int? _parseTotalFromContentRange(String? cr) {
    // e.g. "bytes 12345-999999/1000000"
    if (cr == null) return null;
    final slash = cr.lastIndexOf('/');
    if (slash == -1) return null;
    final totalStr = cr.substring(slash + 1).trim();
    final total = int.tryParse(totalStr);
    return total;
  }

  Future<void> cancel() async {
    isCancelled = true;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}

class DownloadManager extends ChangeNotifier {
  final Map<String, DownloadTask> _tasks = {}; // modelId -> task
  ModelProvider? _modelProvider;

  void attach(ModelProvider provider) {
    _modelProvider = provider;
  }

  DownloadTask? getTask(String modelId) => _tasks[modelId];

  String _normalizeFileName(String displayName) => toGgufFileName(displayName);

  void downloadModel({
    required String modelId,
    required String fileName,   // DISPLAY name (can include '/')
    required String downloadUrl,
  }) {
    if (_tasks.containsKey(modelId) && !_tasks[modelId]!.isDone) {
      debugPrint('ℹ️ Already downloading: $modelId');
      return;
    }

    final normalized = _normalizeFileName(fileName);
    final task = DownloadTask(
      modelId: modelId,
      fileName: normalized,
      downloadUrl: downloadUrl,
    );
    _tasks[modelId] = task;

    task.start(
      onProgress: () => notifyListeners(),
      onCompleteOrError: () {
        if (task.isDone && !task.isCancelled && !task.isError) {
          _modelProvider?.markDownloaded(modelId);
        } else if (task.isError || task.isCancelled) {
          // Keep task entry if you want to show "Retry" button;
          // here we remove it so tile goes back to Download state.
          _tasks.remove(modelId);
        }
        notifyListeners();
      },
      maxRetries: 5,
    );

    notifyListeners(); // initial UI update
  }

  Future<void> cancel(String modelId) async {
    final task = _tasks[modelId];
    if (task == null || task.isDone) return;

    await task.cancel();

    // Keep partial file so a future call will resume
    debugPrint('🛑 Cancelled download for $modelId (partial kept for resume)');

    _tasks.remove(modelId);
    notifyListeners();
  }

  /// Delete a downloaded model (pass DISPLAY name; we sanitize internally).
  Future<void> deleteModel(String displayName, {String? modelId}) async {
    final dir = await getApplicationDocumentsDirectory();
    final normalized = _normalizeFileName(displayName);
    final candidates = <String>{normalized, normalized.replaceAll(' ', '_')};

    for (final name in candidates) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        await f.delete();
        debugPrint('🗑 Deleted: ${f.path}');
      }
    }

    if (modelId != null) {
      _modelProvider?.markUndownloaded(modelId);
    }
    notifyListeners();
  }
}
