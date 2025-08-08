// lib/llm/llama_ffi.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

DynamicLibrary _openBridge() {
  // Android/iOS: name only
  const libName = "libllama_bridge.so";
  try {
    final lib = DynamicLibrary.open(libName);
    if (kDebugMode) {
      print("[FFI] Opened $libName");
    }
    return lib;
  } catch (e) {
    // As fallback (rare), try loading from absolute path in app lib dir
    // But usually not needed; comment this next block if unnecessary.
    if (kDebugMode) {
      print("[FFI] Failed to open $libName via default loader: $e");
    }
    rethrow;
  }
}

// C signatures
typedef _LbLoadNative = Int32 Function(Pointer<Utf8>);
typedef _LbIsLoadedNative = Int32 Function();
typedef _LbFreeNative = Void Function();

// Dart signatures
typedef _LbLoadDart = int Function(Pointer<Utf8>);
typedef _LbIsLoadedDart = int Function();
typedef _LbFreeDart = void Function();

final DynamicLibrary _bridge = _openBridge();

final _LbLoadDart _lbLoad =
    _bridge.lookup<NativeFunction<_LbLoadNative>>('lb_load').asFunction();

final _LbIsLoadedDart _lbIsLoaded =
    _bridge.lookup<NativeFunction<_LbIsLoadedNative>>('lb_is_loaded').asFunction();

final _LbFreeDart _lbFree =
    _bridge.lookup<NativeFunction<_LbFreeNative>>('lb_free').asFunction();

Future<bool> loadModel(String modelName) async {
  final dir = await getApplicationDocumentsDirectory();
  // Your files are like SmolVLM.gguf (no double extension)
  final modelPath = '${dir.path}/${modelName.replaceAll(' ', '_')}';
  if (kDebugMode) {
    print("[FFI] Loading model: $modelPath");
  }

  final f = File(modelPath);
  if (!f.existsSync()) {
    if (kDebugMode) {
      print("❌ Model not found at: $modelPath");
    }
    return false;
  }

  final cPath = modelPath.toNativeUtf8();
  try {
    final rc = _lbLoad(cPath);
    if (kDebugMode) {
      print("[FFI] lb_load rc=$rc");
    }
    return rc == 0 && _lbIsLoaded() == 1;
  } finally {
    malloc.free(cPath);
  }
}

Future<String> runModel(String prompt) async {
  // For now, your C++ bridge doesn’t implement lb_eval returning text.
  // Just return a placeholder until you add lb_eval.
  return "Model loaded ✅ — implement lb_eval in C++ to get real text.";
}

void freeModel() {
  try {
    _lbFree();
  } catch (_) {}
}
