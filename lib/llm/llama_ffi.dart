// lib/llm/llama_ffi.dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

DynamicLibrary _openBridge() {
  final lib = DynamicLibrary.open('libllama_bridge.so');
  debugPrint('[FFI] Opened libllama_bridge.so');
  return lib;
}

final DynamicLibrary _bridge = _openBridge();

// ---------- base FFI ----------

// int lb_load(const char* path)
typedef _LbLoadNative = Int32 Function(Pointer<Utf8>);
typedef _LbLoadDart = int Function(Pointer<Utf8>);
final _LbLoadDart _lbLoad =
    _bridge.lookup<NativeFunction<_LbLoadNative>>('lb_load').asFunction();

// int lb_is_loaded()
typedef _LbIsLoadedNative = Int32 Function();
typedef _LbIsLoadedDart = int Function();
final _LbIsLoadedDart _lbIsLoaded =
    _bridge.lookup<NativeFunction<_LbIsLoadedNative>>('lb_is_loaded').asFunction();

// int lb_reset()
typedef _LbResetNative = Int32 Function();
typedef _LbResetDart = int Function();
final _LbResetDart _lbReset =
    _bridge.lookup<NativeFunction<_LbResetNative>>('lb_reset').asFunction();

// const char* lb_eval(const char* prompt, int max_tokens)
typedef _LbEvalNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _LbEvalDart = Pointer<Utf8> Function(Pointer<Utf8>, int);
final _LbEvalDart _lbEval =
    _bridge.lookup<NativeFunction<_LbEvalNative>>('lb_eval').asFunction();

// void lb_free()
typedef _LbFreeNative = Void Function();
typedef _LbFreeDart = void Function();
final _LbFreeDart _lbFree =
    _bridge.lookup<NativeFunction<_LbFreeNative>>('lb_free').asFunction();

// (optional) void lb_clear_history()
typedef _LbClearHistoryNative = Void Function();
typedef _LbClearHistoryDart = void Function();
// Bind if available; null if symbol doesn't exist.
final _LbClearHistoryDart? _lbClearHistory = (() {
  try {
    return _bridge
        .lookup<NativeFunction<_LbClearHistoryNative>>('lb_clear_history')
        .asFunction<_LbClearHistoryDart>();
  } catch (_) {
    return null;
  }
})();

// ---------- streaming FFI ----------

// int lb_stream_begin(const char* prompt, int max_tokens)
typedef _LbStreamBeginNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _LbStreamBeginDart = int Function(Pointer<Utf8>, int);
final _LbStreamBeginDart _lbStreamBegin = _bridge
    .lookup<NativeFunction<_LbStreamBeginNative>>('lb_stream_begin')
    .asFunction();

// const char* lb_stream_next()
typedef _LbStreamNextNative = Pointer<Utf8> Function();
typedef _LbStreamNextDart = Pointer<Utf8> Function();
final _LbStreamNextDart _lbStreamNext = _bridge
    .lookup<NativeFunction<_LbStreamNextNative>>('lb_stream_next')
    .asFunction();

// int lb_stream_is_running()
typedef _LbStreamIsRunningNative = Int32 Function();
typedef _LbStreamIsRunningDart = int Function();
final _LbStreamIsRunningDart _lbStreamIsRunning = _bridge
    .lookup<NativeFunction<_LbStreamIsRunningNative>>('lb_stream_is_running')
    .asFunction();

// void lb_stream_cancel()
typedef _LbStreamCancelNative = Void Function();
typedef _LbStreamCancelDart = void Function();
final _LbStreamCancelDart _lbStreamCancel = _bridge
    .lookup<NativeFunction<_LbStreamCancelNative>>('lb_stream_cancel')
    .asFunction();

// ---------- public helpers (call from the worker isolate) ----------

int ffiLoadModelAtPath(String fullPath) {
  final p = fullPath.toNativeUtf8();
  try {
    return _lbLoad(p);
  } finally {
    calloc.free(p);
  }
}

bool ffiIsLoaded() => _lbIsLoaded() != 0;

int ffiReset() => _lbReset();

String ffiEval(String prompt, int maxTokens) {
  final p = prompt.toNativeUtf8();
  try {
    final res = _lbEval(p, maxTokens);
    return res.cast<Utf8>().toDartString();
  } catch (_) {
    return 'Evaluation failed.';
  } finally {
    calloc.free(p);
  }
}

void ffiFree() => _lbFree();

void ffiClearHistory() {
  // Call only if the native symbol exists
  final fn = _lbClearHistory;
  if (fn != null) fn();
}

// ----- streaming helpers -----

int ffiStreamBegin(String prompt, int maxTokens) {
  final p = prompt.toNativeUtf8();
  try {
    return _lbStreamBegin(p, maxTokens);
  } finally {
    calloc.free(p);
  }
}

String? ffiStreamNext() {
  final ptr = _lbStreamNext();
  if (ptr.address == 0) return null; // native error
  return ptr.cast<Utf8>().toDartString();
}

bool ffiStreamIsRunning() => _lbStreamIsRunning() != 0;

void ffiStreamCancel() => _lbStreamCancel();
