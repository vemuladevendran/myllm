// lib/llm/llama_worker.dart
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'llama_ffi.dart';

enum _Cmd { loadPath, eval, reset, clear, unload, isLoaded }

class LlamaWorker {
  static final LlamaWorker _singleton = LlamaWorker._();
  LlamaWorker._();
  factory LlamaWorker() => _singleton;

  Isolate? _iso;
  SendPort? _send;
  final _resp = ReceivePort();

  Future<void> start() async {
    if (_iso != null) return;
    _iso = await Isolate.spawn(_entry, _resp.sendPort);
    _send = await _resp.first as SendPort;
  }

  Future<void> stop() async {
    _send?.send([_Cmd.unload.index, null]);
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _send = null;
  }

  // NEW: load by full file path (UI isolate must compute it)
  Future<bool> loadModelAtPath(String fullPath) async {
    final r = ReceivePort();
    _send!.send([_Cmd.loadPath.index, [fullPath], r.sendPort]);
    return await r.first as bool;
  }

  Future<bool> isLoaded() async {
    final r = ReceivePort();
    _send!.send([_Cmd.isLoaded.index, null, r.sendPort]);
    return await r.first as bool;
  }

  Future<String> eval(String prompt, {int maxTokens = 128}) async {
    final r = ReceivePort();
    _send!.send([_Cmd.eval.index, [prompt, maxTokens], r.sendPort]);
    return await r.first as String;
  }

  Future<bool> reset() async {
    final r = ReceivePort();
    _send!.send([_Cmd.reset.index, null, r.sendPort]);
    return await r.first as bool;
  }

  Future<void> clearHistory() async {
    final r = ReceivePort();
    _send!.send([_Cmd.clear.index, null, r.sendPort]);
    await r.first;
  }

  static void _entry(SendPort mainSend) async {
    final inbox = ReceivePort();
    mainSend.send(inbox.sendPort);
    await _WorkerImpl().loop(inbox);
  }
}

class _WorkerImpl {
  final _inProgress = ValueNotifier<bool>(false);

  Future<void> loop(ReceivePort inbox) async {
    await for (final msg in inbox) {
      final list = msg as List;
      final cmd = _Cmd.values[list[0] as int];
      final args = list[1];
      final SendPort? reply = list.length > 2 ? list[2] as SendPort : null;

      switch (cmd) {
        case _Cmd.loadPath:
          {
            final fullPath = (args as List)[0] as String;
            final ok = await loadModelAtPath(fullPath);
            reply?.send(ok);
          }
          break;
        case _Cmd.eval:
          {
            if (_inProgress.value) {
              reply?.send('Busy; try again');
              break;
            }
            _inProgress.value = true;
            final a = args as List;
            final prompt = a[0] as String;
            final maxT = a[1] as int;
            final out = await runModel(prompt, maxTokens: maxT);
            _inProgress.value = false;
            reply?.send(out);
          }
          break;
        case _Cmd.reset:
          {
            final ok = await resetContext();
            reply?.send(ok);
          }
          break;
        case _Cmd.clear:
          {
            clearHistory();
            reply?.send(true);
          }
          break;
        case _Cmd.unload:
          {
            unloadModel();
            reply?.send(true);
          }
          break;
        case _Cmd.isLoaded:
          {
            reply?.send(isLoaded);
          }
          break;
      }
    }
  }
}
