// lib/llm/llama_ffi.dart
//
// Minimal, production-ready FFI bindings for llama_bridge.{so}
// Exposes: loadModel, runModel, resetContext, clearHistory, unloadModel
//
// NOTE: This assumes:
//   - android/app/src/main/jniLibs/arm64-v8a/libllama.so  (prebuilt from llama.cpp)
//   - android builds a shared "llama_bridge" from your C++ file (llama_bridge.cpp)
//   - libllama_bridge.so is loadable at runtime
//
// If you rename symbols in C++ side, update lookups here accordingly.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show File, Platform;

DynamicLibrary _openBridge() {
  // On Android, the linker finds libs by soname inside the app package.
  // If you change the output name in CMake, update this string.
  if (!Platform.isAndroid) {
    throw UnsupportedError('llama_ffi is currently Android-only.');
  }
  final lib = DynamicLibrary.open('libllama_bridge.so');
  debugPrint('[FFI] Opened libllama_bridge.so');
  return lib;
}

final DynamicLibrary _bridge = _openBridge();

/// -------------------------
/// Native type definitions
/// -------------------------

// int lb_load(const char* path)
typedef _LbLoadNative = Int32 Function(Pointer<Utf8>);
typedef _LbLoadDart = int Function(Pointer<Utf8>);

// int lb_is_loaded()
typedef _LbIsLoadedNative = Int32 Function();
typedef _LbIsLoadedDart = int Function();

// int lb_reset()
typedef _LbResetNative = Int32 Function();
typedef _LbResetDart = int Function();

// const char* lb_eval(const char* prompt, int max_tokens)
typedef _LbEvalNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _LbEvalDart = Pointer<Utf8> Function(Pointer<Utf8>, int);

// void lb_free()
typedef _LbFreeNative = Void Function();
typedef _LbFreeDart = void Function();

// void lb_clear_history()
typedef _LbClearHistoryNative = Void Function();
typedef _LbClearHistoryDart = void Function();

/// -------------------------
/// Symbol lookups
/// -------------------------

final _LbLoadDart _lbLoad =
    _bridge.lookup<NativeFunction<_LbLoadNative>>('lb_load').asFunction();

final _LbIsLoadedDart _lbIsLoaded =
    _bridge.lookup<NativeFunction<_LbIsLoadedNative>>('lb_is_loaded').asFunction();

final _LbResetDart _lbReset =
    _bridge.lookup<NativeFunction<_LbResetNative>>('lb_reset').asFunction();

final _LbEvalDart _lbEval =
    _bridge.lookup<NativeFunction<_LbEvalNative>>('lb_eval').asFunction();

final _LbFreeDart _lbFree =
    _bridge.lookup<NativeFunction<_LbFreeNative>>('lb_free').asFunction();

final _LbClearHistoryDart _lbClearHistory =
    _bridge.lookup<NativeFunction<_LbClearHistoryNative>>('lb_clear_history').asFunction();

/// -------------------------
/// Public helpers (safe API)
/// -------------------------

/// Load a `.gguf` stored in app documents directory.
/// You can pass with or without ".gguf" extension.
/// Returns true if model & context are ready.
Future<bool> loadModel(String modelFileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final hasExt = modelFileName.toLowerCase().endsWith('.gguf');
  final fullPath = '${dir.path}/${hasExt ? modelFileName : '$modelFileName.gguf'}';

  debugPrint('[FFI] Loading model: $fullPath');

  final p = fullPath.toNativeUtf8();
  try {
    final rc = _lbLoad(p);
    final ok = rc == 0 && _lbIsLoaded() != 0;
    debugPrint('[FFI] lb_load rc=$rc, isLoaded=$ok');
    return ok;
  } catch (e) {
    debugPrint('❌ lb_load threw: $e');
    return false;
  } finally {
    calloc.free(p);
  }
}

/// Evaluate a prompt with a max token budget.
/// NOTE: This call is synchronous and will block the thread.
/// Run it off the UI thread (e.g., in an isolate) if your model is slow.
Future<String> runModel(String prompt, {int maxTokens = 128}) async {
  if (_lbIsLoaded() == 0) return 'Model not loaded.';
  debugPrint("[FFI] eval(prompt='${_shorten(prompt)}', maxTokens=$maxTokens)");

  final p = prompt.toNativeUtf8();
  try {
    final resPtr = _lbEval(p, maxTokens);
    final out = resPtr.cast<Utf8>().toDartString();
    debugPrint("[FFI] eval -> '${_shorten(out)}'");
    return out;
  } catch (e) {
    debugPrint('❌ lb_eval threw: $e');
    return 'Evaluation failed.';
  } finally {
    calloc.free(p);
  }
}

/// Recreate context (clears KV + resets internal state)
Future<bool> resetContext() async {
  if (_lbIsLoaded() == 0) return false;
  try {
    final rc = _lbReset();
    debugPrint('[FFI] lb_reset rc=$rc');
    return rc == 0;
  } catch (e) {
    debugPrint('❌ lb_reset threw: $e');
    return false;
  }
}

/// Clears history (KV cache) without recreating the context.
/// Use this for "New chat" UX.
void clearHistory() {
  try {
    _lbClearHistory();
    debugPrint('[FFI] lb_clear_history done');
  } catch (e) {
    debugPrint('❌ lb_clear_history threw: $e');
  }
}

/// Dispose all native resources (model, context, backend).
void unloadModel() {
  try {
    _lbFree();
    debugPrint('[FFI] lb_free done');
  } catch (e) {
    debugPrint('❌ lb_free threw: $e');
  }
}


// === Add to lib/llm/llama_ffi.dart ===

Future<bool> loadModelAtPath(String fullPath) async {
  debugPrint('[FFI] Loading model (full path): $fullPath');
  final p = fullPath.toNativeUtf8();
  try {
    final rc = _lbLoad(p);
    final ok = rc == 0 && _lbIsLoaded() != 0;
    debugPrint('[FFI] lb_load rc=$rc, isLoaded=$ok');
    return ok;
  } catch (e) {
    debugPrint('❌ lb_load (full path) threw: $e');
    return false;
  } finally {
    calloc.free(p);
  }
}


/// Convenience: are we loaded?
bool get isLoaded => _lbIsLoaded() != 0;

/// -------------------------
/// Small utilities
/// -------------------------

String _shorten(String s, {int max = 80}) {
  final oneLine = s.replaceAll('\n', ' ');
  if (oneLine.length <= max) return oneLine;
  return '${oneLine.substring(0, max)}…';
}
