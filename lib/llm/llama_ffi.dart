import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

DynamicLibrary _bridge() {
  final lib = DynamicLibrary.open("libllama_bridge.so");
  print("[FFI] Opened libllama_bridge.so");
  return lib;
}

// FFI typedefs
typedef _LbLoadNative = Int32 Function(Pointer<Utf8>);
typedef _LbLoadDart   = int Function(Pointer<Utf8>);

typedef _LbEvalNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _LbEvalDart   = Pointer<Utf8> Function(Pointer<Utf8>, int);

typedef _LbFreeNative = Void Function();
typedef _LbFreeDart   = void Function();

typedef _LbIsLoadedNative = Int32 Function();
typedef _LbIsLoadedDart   = int Function();

// Resolved symbols
late final _LbLoadDart _lbLoad     = _bridge().lookupFunction<_LbLoadNative, _LbLoadDart>('lb_load');
late final _LbEvalDart _lbEval     = _bridge().lookupFunction<_LbEvalNative, _LbEvalDart>('lb_eval');
late final _LbFreeDart _lbFree     = _bridge().lookupFunction<_LbFreeNative, _LbFreeDart>('lb_free');
late final _LbIsLoadedDart _lbIs   = _bridge().lookupFunction<_LbIsLoadedNative, _LbIsLoadedDart>('lb_is_loaded');

Future<bool> loadModel(String modelName) async {
  // Your downloader saves: /data/user/0/<pkg>/app_flutter/<Name>.gguf
  final modelPath = "/data/user/0/com.example.myllm/app_flutter/${modelName.replaceAll(' ','_')}.gguf";
  print("[FFI] Loading model: $modelPath");
  try {
    final cPath = modelPath.toNativeUtf8();
    final rc = _lbLoad(cPath);
    calloc.free(cPath);
    final loaded = _lbIs() == 1;
    print("[FFI] lb_load rc=$rc, isLoaded=$loaded");
    return rc == 0 && loaded;
  } catch (e) {
    print("❌ lb_load threw: $e");
    return false;
  }
}

Future<String> runModel(String prompt, {int maxTokens = 64}) async {
  print("[FFI] eval(prompt='${prompt.replaceAll('\n',' ')}', maxTokens=$maxTokens)");
  final p = prompt.toNativeUtf8();
  try {
    final resPtr = _lbEval(p, maxTokens);
    final out = resPtr.toDartString();
    print("[FFI] eval -> '${out.length > 200 ? out.substring(0,200)+'...' : out}'");
    return out;
  } catch (e) {
    print("❌ lb_eval threw: $e");
    return "❌ eval error: $e";
  } finally {
    calloc.free(p);
  }
}

void freeModel() {
  try {
    _lbFree();
    print("[FFI] lb_free ok");
  } catch (e) {
    print("❌ lb_free threw: $e");
  }
}
