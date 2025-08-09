// lib/llm/llama_ffi.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// load our bridge .so
DynamicLibrary _openBridge() {
  final lib = DynamicLibrary.open('libllama_bridge.so');
  if (kDebugMode) print('[FFI] Opened libllama_bridge.so');
  return lib;
}

typedef _LbLoadNative     = Int32 Function(Pointer<Utf8>);
typedef _LbIsLoadedNative = Int32 Function();
typedef _LbFreeNative     = Void Function();
typedef _LbEvalNative     = Pointer<Utf8> Function(Pointer<Utf8>, Int32);

typedef _LbLoadDart     = int Function(Pointer<Utf8>);
typedef _LbIsLoadedDart = int Function();
typedef _LbFreeDart     = void Function();
typedef _LbEvalDart     = Pointer<Utf8> Function(Pointer<Utf8>, int);

final _bridge = _openBridge();

late final _LbLoadDart _lbLoad =
    _bridge.lookup<NativeFunction<_LbLoadNative>>('lb_load').asFunction();
late final _LbIsLoadedDart _lbIsLoaded =
    _bridge.lookup<NativeFunction<_LbIsLoadedNative>>('lb_is_loaded').asFunction();
late final _LbFreeDart _lbFree =
    _bridge.lookup<NativeFunction<_LbFreeNative>>('lb_free').asFunction();
late final _LbEvalDart _lbEval =
    _bridge.lookup<NativeFunction<_LbEvalNative>>('lb_eval').asFunction();

/// Loads `/data/user/0/<pkg>/files/<modelName>.gguf`
Future<bool> loadModel(String modelName) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/${modelName.replaceAll(' ', '_')}';
  if (kDebugMode) print('[FFI] Loading model: $path');

  final f = File(path);
  if (!f.existsSync()) {
    if (kDebugMode) print('❌ Model not found: $path');
    return false;
  }

  final cPath = path.toNativeUtf8();
  try {
    final rc = _lbLoad(cPath);
    if (kDebugMode) print('[FFI] lb_load rc=$rc, isLoaded=${_lbIsLoaded()}');
    return rc == 0 && _lbIsLoaded() == 1;
  } catch (e) {
    if (kDebugMode) print('❌ lb_load threw: $e');
    return false;
  } finally {
    malloc.free(cPath);
  }
}

Future<String> runModel(String prompt) async {
  if (_lbIsLoaded() != 1) return 'Model NOT loaded';
  final cPrompt = prompt.toNativeUtf8();
  try {
    final ptr = _lbEval(cPrompt, 64);
    final text = ptr.cast<Utf8>().toDartString(); // from static buffer (don't free)
    return text;
  } catch (e) {
    return 'lb_eval error: $e';
  } finally {
    malloc.free(cPrompt);
  }
}

void freeModel() {
  try { _lbFree(); } catch (_) {}
  if (kDebugMode) print('[FFI] freed');
}
