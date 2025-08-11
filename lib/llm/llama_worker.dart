// lib/llm/llama_worker.dart
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'llama_ffi.dart';

class LlamaWorker {
  Isolate? _iso;
  SendPort? _send;
  StreamSubscription? _sub;
  final _ready = Completer<void>();

  bool get isRunning => _iso != null && _send != null;

  Future<void> start({Duration initTimeout = const Duration(seconds: 5)}) async {
    if (_iso != null) return;
    final rp = ReceivePort();
    _iso = await Isolate.spawn(_entry, rp.sendPort, debugName: 'llama_worker');
    _sub = rp.listen((dynamic message) {
      if (message is SendPort) {
        _send = message;
        if (!_ready.isCompleted) _ready.complete();
      }
    });

    await _ready.future.timeout(initTimeout, onTimeout: () {
      throw TimeoutException('Worker init timeout');
    });
  }

  Future<void> stop() async {
    try {
      if (_send != null) {
        await _sendRequest({'op': 'stop'}, timeout: const Duration(seconds: 2));
      }
    } catch (_) {}
    _sub?.cancel();
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _send = null;
  }

  Future<void> _ensureReady() async {
    if (_send != null) return;
    if (_iso == null) {
      await start();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_send == null) throw StateError('Worker not ready');
  }

  Future<bool> loadModelAtPath(String fullPath,
      {Duration timeout = const Duration(seconds: 90)}) async {
    await _ensureReady();
    final res = await _sendRequest({'op': 'load', 'path': fullPath}, timeout: timeout);
    return (res['ok'] as bool? ?? false);
  }

  Future<String> eval(String prompt,
      {int maxTokens = 64, Duration timeoutPerCall = const Duration(seconds: 90)}) async {
    await _ensureReady();
    final res = await _sendRequest(
      {'op': 'eval', 'prompt': prompt, 'max': maxTokens},
      timeout: timeoutPerCall,
    );
    return (res['text'] as String?) ?? 'Evaluation failed.';
  }

  Future<void> clearHistory() async {
    await _ensureReady();
    await _sendRequest({'op': 'clear'}, timeout: const Duration(seconds: 3));
  }

  /// Streamed generation with a watchdog.
  /// - onToken: called on every emitted text piece (may be small).
  /// - maxSilence: if no piece/tick received for this long, we cancel and error.
  Future<String> streamEval(
    String prompt, {
    required void Function(String piece) onToken,
    int maxTokens = 256,
    Duration maxTotalTime = const Duration(seconds: 180),
    Duration maxSilence = const Duration(seconds: 15),
  }) async {
    await _ensureReady();

    final rp = ReceivePort();
    _send!.send([rp.sendPort, {
      'op': 'stream_eval',
      'prompt': prompt,
      'max': maxTokens,
    }]);

    final buf = StringBuffer();
    final started = DateTime.now();
    DateTime lastActivity = DateTime.now();

    late StreamSubscription sub;
    final completer = Completer<void>();

    // Watchdog: if no activity for maxSilence OR wall time > maxTotalTime, cancel in worker & fail.
    Timer? watchdog;
    void _resetWatchdog() {
      watchdog?.cancel();
      final remaining = maxTotalTime - DateTime.now().difference(started);
      final next = remaining <= Duration.zero ? Duration(milliseconds: 1) : maxSilence;
      watchdog = Timer(next, () async {
        if (DateTime.now().difference(lastActivity) >= maxSilence ||
            DateTime.now().difference(started) >= maxTotalTime) {
          try {
            // Ask worker to cancel the native stream, then close our port
            await _sendRequest({'op': 'stream_cancel'}, timeout: const Duration(seconds: 2));
          } catch (_) {}
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException('stream stalled/timeout'));
          }
          await sub.cancel();
          rp.close();
        } else {
          _resetWatchdog();
        }
      });
    }
    _resetWatchdog();

    sub = rp.listen((dynamic msg) {
      lastActivity = DateTime.now();
      if (msg is Map) {
        final kind = msg['kind'];
        if (kind == 'piece') {
          final s = (msg['text'] as String?) ?? '';
          if (s.isNotEmpty) {
            buf.write(s);
            onToken(s);
          }
          _resetWatchdog();
        } else if (kind == 'tick') {
          // heartbeat – just reset watchdog
          _resetWatchdog();
        } else if (kind == 'end') {
          if (!completer.isCompleted) completer.complete();
          sub.cancel();
          rp.close();
        } else if (kind == 'error' || msg['error'] != null) {
          if (!completer.isCompleted) {
            completer.completeError(StateError(msg['error'] as String? ?? 'stream error'));
          }
          sub.cancel();
          rp.close();
        }
      }
    });

    // Wait for completion or error
    await completer.future;
    watchdog?.cancel();

    return buf.toString();
  }

  // ----- request/response core -----
  Future<Map<String, dynamic>> _sendRequest(Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_send == null) throw StateError('Worker not started');
    final rp = ReceivePort();
    _send!.send([rp.sendPort, body]);
    final resp = await rp.first.timeout(timeout, onTimeout: () {
      rp.close();
      throw TimeoutException('Worker request timed out: ${body['op']}');
    });
    rp.close();
    return (resp as Map).cast<String, dynamic>();
  }

  // ----- isolate entry -----
  static void _entry(SendPort host) {
    final inbox = ReceivePort();
    host.send(inbox.sendPort);

    bool loaded = false;
    bool streaming = false; // guard against multiple overlapping streams

    Future<Map<String, dynamic>> _handle(Map<String, dynamic> body) async {
      final op = body['op'] as String? ?? '';
      try {
        switch (op) {
          case 'load': {
            final path = body['path'] as String? ?? '';
            debugPrint('[WK] load: $path');
            final rc = ffiLoadModelAtPath(path);
            loaded = (rc == 0) && ffiIsLoaded();
            return {'ok': loaded, 'rc': rc};
          }
          case 'eval': {
            if (!loaded || !ffiIsLoaded()) return {'text': 'Model not loaded.'};
            final prompt = body['prompt'] as String? ?? '';
            final max = body['max'] as int? ?? 64;
            final out = ffiEval(prompt, max);
            return {'text': out};
          }
          case 'clear': {
            if (loaded) { ffiClearHistory(); }
            return {'ok': true};
          }
          case 'stop': {
            if (loaded) { try { ffiFree(); } catch (_) {} }
            return {'ok': true};
          }
          case 'stream_cancel': {
            if (streaming) {
              try { ffiStreamCancel(); } catch (_) {}
              streaming = false;
            }
            return {'ok': true};
          }
          default:
            return {'error': 'unknown op'};
        }
      } catch (e) {
        return {'error': e.toString()};
      }
    }

    inbox.listen((dynamic raw) async {
      if (raw is List && raw.length == 2 && raw[0] is SendPort && raw[1] is Map) {
        final SendPort reply = raw[0] as SendPort;
        final Map<String, dynamic> body = (raw[1] as Map).cast<String, dynamic>();
        final op = body['op'] as String? ?? '';

        if (op != 'stream_eval') {
          final res = await _handle(body);
          reply.send(res);
          return;
        }

        // --- streaming path ---
        try {
          if (streaming) {
            reply.send({'error': 'another stream in progress'});
            return;
          }
          if (!loaded || !ffiIsLoaded()) {
            reply.send({'error': 'Model not loaded'});
            return;
          }
          streaming = true;

          final prompt = body['prompt'] as String? ?? '';
          final max = body['max'] as int? ?? 256;

          final rc = ffiStreamBegin(prompt, max);
          if (rc != 0) {
            streaming = false;
            reply.send({'error': 'stream begin rc=$rc'});
            return;
          }

          int idleIters = 0;
          const idleHeartbeatEvery = 4; // send a tick every few empties

          while (ffiStreamIsRunning()) {
            final s = ffiStreamNext(); // null=error, ""=no piece/finished, else piece
            if (s == null) {
              streaming = false;
              reply.send({'error': 'stream next error'});
              return;
            }
            if (s.isNotEmpty) {
              idleIters = 0;
              reply.send({'kind': 'piece', 'text': s});
            } else {
              idleIters++;
              if (idleIters % idleHeartbeatEvery == 0) {
                reply.send({'kind': 'tick'});
              }
            }
            // no sleep: llama_decode blocks per token already
          }

          streaming = false;
          reply.send({'kind': 'end'});
        } catch (e) {
          streaming = false;
          reply.send({'error': e.toString()});
        }
      }
    });
  }
}
