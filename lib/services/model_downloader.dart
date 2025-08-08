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

      print("📥 Starting download for: $modelId");
      print("⬇️ Download URL: $downloadUrl");
      print("📁 Saving to: $filePath");

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        print("❌ Failed to download. Status: ${response.statusCode}");
        isError = true;
        onError();
        return;
      }

      total = response.contentLength ?? 1;
      final sink = file.openWrite();

      _subscription = response.stream.listen(
        (List<int> chunk) {
          received += chunk.length;
          sink.add(chunk);
          // 🔄 Real-time update
          onComplete();
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          isDone = true;
          print("✅ Download complete: $filePath");
          onComplete();
        },
        onError: (e) async {
          print("❌ Error during download: $e");
          isError = true;
          await sink.close();
          onError();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("❌ Download exception: $e");
      isError = true;
      onError();
    }
  }

  Future<void> cancel() async {
    print("🛑 Canceling download: $modelId");
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

    print("🚀 Initiating download for model: $modelId");

    final task = DownloadTask(
      modelId: modelId,
      fileName: fileName,
      downloadUrl: downloadUrl,
    );

    _tasks[modelId] = task;

    task.start(
      () {
        notifyListeners(); // Real-time update
      },
      () {
        notifyListeners(); // Error update
      },
    );

    notifyListeners(); // Initial UI update
  }

  Future<void> deleteModel(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName.gguf';
    final file = File(filePath);

    print("🗑 Attempting to delete: $filePath");

    if (await file.exists()) {
      await file.delete();
      print("✅ File deleted: $filePath");
    } else {
      print("⚠️ File not found for deletion: $filePath");
    }

    notifyListeners();
  }

  void cancel(String modelId) async {
    print("🛑 Cancel request for: $modelId");
    await _tasks[modelId]?.cancel();
    _tasks.remove(modelId);
    notifyListeners();
  }

  DownloadTask? getTask(String modelId) => _tasks[modelId];
}
