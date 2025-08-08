// lib/llm/llama_ffi.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

// -----------------------------
// Top‑level FFI typedefs
// -----------------------------
// C: const char* lb_load(const char* model_path);
typedef LbLoadNative = Pointer<Utf8> Function(Pointer<Utf8>);
// Dart: same param types, but Dart value types where applicable
typedef LbLoadDart = Pointer<Utf8> Function(Pointer<Utf8>);

// C: const char* lb_eval(const char* prompt, int n_predict);
typedef LbEvalNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef LbEvalDart   = Pointer<Utf8> Function(Pointer<Utf8>, int);

// C: void lb_free(void* p);
typedef LbFreeNative = Void Function(Pointer<Void>);
typedef LbFreeDart   = void Function(Pointer<Void>);

// -----------------------------
// Load the llama bridge library
// -----------------------------
final DynamicLibrary _lib = DynamicLibrary.open('libllama.so');

// Look up exported functions
final LbLoadDart _lbLoad =
    _lib.lookupFunction<LbLoadNative, LbLoadDart>('lb_load');

final LbEvalDart _lbEval =
    _lib.lookupFunction<LbEvalNative, LbEvalDart>('lb_eval');

final LbFreeDart _lbFree =
    _lib.lookupFunction<LbFreeNative, LbFreeDart>('lb_free');

// -----------------------------
// Simple runtime wrapper
// -----------------------------
class LlamaRuntime {
  LlamaRuntime._();
  static final LlamaRuntime instance = LlamaRuntime._();

  bool _isLoaded = false;
  String? _currentModelPath;

  bool get isLoaded => _isLoaded;
  String? get currentModelPath => _currentModelPath;

  Future<String> _resolveModelPath(String modelName) async {
    final dir = await getApplicationDocumentsDirectory();
    final base = modelName.replaceAll(' ', '_');
    final withExt = '${dir.path}/$base.gguf';
    final withoutExt = '${dir.path}/$base';

    if (File(withExt).existsSync()) return withExt;
    if (File(withoutExt).existsSync()) return withoutExt;
    // default to withExt path so logs are consistent
    return withExt;
  }

  Future<bool> loadByModelName(String modelName) async {
    final path = await _resolveModelPath(modelName);
    return load(path);
  }

  Future<bool> load(String modelPath) async {
    print('[FFI] Loading model: $modelPath');

    final f = File(modelPath);
    if (!f.existsSync()) {
      print('❌ Model not found: $modelPath');
      _isLoaded = false;
      _currentModelPath = null;
      return false;
    }

    final cPath = modelPath.toNativeUtf8();
    try {
      // lb_load returns NULL on success, or a C string (error message) on failure
      final errPtr = _lbLoad(cPath);
      if (errPtr != nullptr) {
        final errMsg = errPtr.toDartString();
        // free the C string allocated by native
        _lbFree(errPtr.cast());
        print('❌ lb_load error: $errMsg');
        _isLoaded = false;
        _currentModelPath = null;
        return false;
      }

      _isLoaded = true;
      _currentModelPath = modelPath;
      print('✅ Model loaded OK.');
      return true;
    } catch (e) {
      print('❌ Exception calling lb_load: $e');
      _isLoaded = false;
      _currentModelPath = null;
      return false;
    } finally {
      malloc.free(cPath);
    }
  }

  Future<String> run(String prompt, {int nPredict = 128}) async {
    if (!_isLoaded) {
      return 'Model is not loaded.';
    }

    final cPrompt = prompt.toNativeUtf8();
    try {
      final outPtr = _lbEval(cPrompt, nPredict);
      if (outPtr == nullptr) {
        return '❌ lb_eval returned null';
      }
      final text = outPtr.toDartString();
      // free the C string returned by native
      _lbFree(outPtr.cast());
      return text;
    } catch (e) {
      return '❌ Exception calling lb_eval: $e';
    } finally {
      malloc.free(cPrompt);
    }
  }
}

// -----------------------------
// Top‑level helpers for your UI
// -----------------------------
Future<bool> loadModel(String modelName) =>
    LlamaRuntime.instance.loadByModelName(modelName);

Future<String> runModel(String prompt, {int nPredict = 128}) =>
    LlamaRuntime.instance.run(prompt, nPredict: nPredict);
