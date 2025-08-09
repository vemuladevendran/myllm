import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

DynamicLibrary _openBridge() {
  final lib = DynamicLibrary.open('libllama_bridge.so');
  debugPrint('[FFI] Opened libllama_bridge.so');
  return lib;
}

final DynamicLibrary _bridge = _openBridge();

// int lb_load(const char* path)
typedef _LbLoadNative = Int32 Function(Pointer<Utf8>);
typedef _LbLoadDart   = int Function(Pointer<Utf8>);
final _LbLoadDart _lbLoad =
    _bridge.lookup<NativeFunction<_LbLoadNative>>('lb_load').asFunction();

// int lb_is_loaded()
typedef _LbIsLoadedNative = Int32 Function();
typedef _LbIsLoadedDart   = int Function();
final _LbIsLoadedDart _lbIsLoaded =
    _bridge.lookup<NativeFunction<_LbIsLoadedNative>>('lb_is_loaded').asFunction();

// int lb_reset()
typedef _LbResetNative = Int32 Function();
typedef _LbResetDart   = int Function();
final _LbResetDart _lbReset =
    _bridge.lookup<NativeFunction<_LbResetNative>>('lb_reset').asFunction();

// const char* lb_eval(const char* prompt, int max_tokens)
typedef _LbEvalNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _LbEvalDart   = Pointer<Utf8> Function(Pointer<Utf8>, int);
final _LbEvalDart _lbEval =
    _bridge.lookup<NativeFunction<_LbEvalNative>>('lb_eval').asFunction();

// void lb_free()
typedef _LbFreeNative = Void Function();
typedef _LbFreeDart   = void Function();
final _LbFreeDart _lbFree =
    _bridge.lookup<NativeFunction<_LbFreeNative>>('lb_free').asFunction();

/// Load a `.gguf` stored in app documents directory
/// You can pass with or without ".gguf" extension.
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

Future<String> runModel(String prompt, {int maxTokens = 250}) async {
  if (_lbIsLoaded() == 0) return 'Model not loaded.';
  debugPrint("[FFI] eval(prompt='$prompt', maxTokens=$maxTokens)");
  final p = prompt.toNativeUtf8();
  try {
    final res = _lbEval(p, maxTokens);
    final out = res.cast<Utf8>().toDartString();
    debugPrint("[FFI] eval -> '$out'");
    return out;
  } catch (e) {
    debugPrint('❌ lb_eval threw: $e');
    return 'Evaluation failed.';
  } finally {
    calloc.free(p);
  }
}

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

void unloadModel() {
  try {
    _lbFree();
    debugPrint('[FFI] lb_free done');
  } catch (e) {
    debugPrint('❌ lb_free threw: $e');
  }
}
