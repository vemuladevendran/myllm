import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Load the llama.so file
final llamaLib = DynamicLibrary.open("libllama.so");

// Declare native functions
typedef LlamaInitNative = Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>);
typedef LlamaInit = Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>);

final llama_init_from_file =
    llamaLib.lookupFunction<LlamaInitNative, LlamaInit>('llama_init_from_file');

// Global context
Pointer<Void> globalCtx = nullptr;

/// 🟢 Load the model from given path
String loadModel(String modelPath) {
  final file = File(modelPath);
  if (!file.existsSync()) {
    return "Model file not found at $modelPath";
  }

  final pathPtr = modelPath.toNativeUtf8();
  final Pointer<Void> params = calloc<Uint8>() as Pointer<Void>; // TODO: replace with actual params later

  globalCtx = llama_init_from_file(pathPtr, params);

  calloc.free(pathPtr);
  calloc.free(params);

  if (globalCtx == nullptr) {
    return "❌ Failed to load model!";
  }

  return "✅ Model loaded successfully!";
}
