import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadTask {
  final String modelId;
  final String fileName;
  final String downloadUrl;

  int received = 0;
  int total = 1;
  bool isDone = false;
  bool isError = false;

  StreamSubscription<List<int>>? _subscription;

  DownloadTask({
    required this.modelId,
    required this.fileName,
    required this.downloadUrl,
  });

  double get progress => received / total;

  Future<void> start(VoidCallback onComplete, Function onError) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName.gguf';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        isError = true;
        onError();
        return;
      }

      total = response.contentLength ?? 1;
      final sink = file.openWrite();

      _subscription = response.stream.listen(
        (List<int> chunk) {
          // ✅ FIXED: explicitly typed
          received += chunk.length; // ✅ No type error now
          sink.add(chunk);
        },

        onDone: () async {
          await sink.flush();
          await sink.close();
          isDone = true;
          onComplete();
        },
        onError: (e) async {
          isError = true;
          await sink.close();
          onError();
        },
        cancelOnError: true,
      );
    } catch (_) {
      isError = true;
      onError();
    }
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
  }
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  DownloadManager._internal();

  final Map<String, DownloadTask> _tasks = {};

  void downloadModel({
    required String modelId,
    required String fileName,
    required String downloadUrl,
  }) {
    if (_tasks.containsKey(modelId)) return;

    final task = DownloadTask(
      modelId: modelId,
      fileName: fileName,
      downloadUrl: downloadUrl,
    );

    _tasks[modelId] = task;

    task.start(
      () {
        notifyListeners();
      },
      () {
        notifyListeners();
      },
    );

    notifyListeners();
  }

  Future<void> deleteModel(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName.gguf';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    notifyListeners();
  }

  void cancel(String modelId) async {
    await _tasks[modelId]?.cancel();
    _tasks.remove(modelId);
    notifyListeners();
  }

  DownloadTask? getTask(String modelId) => _tasks[modelId];
}
