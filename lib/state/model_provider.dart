import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/model_metadata.dart';
import '../services/file_naming.dart'; // toGgufFileName, legacyUnderscoreVariant

class ModelProvider with ChangeNotifier {
  // Display names remain untouched in UI.
  List<ModelMetadata> _models = [
    ModelMetadata(
      id: 'unsloth/gemma-3-1b-it-GGUF',
      name: 'Small Model',
      description: 'Gemma is a family of lightweight, state-of-the-art open models from Google, built from the same research and technology used to create the Gemini models.',
      sizeMB: 650.0,
      downloadUrl:
          'https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-UD-IQ1_M.gguf?download=true',
      hfUrl: 'https://huggingface.co/unsloth/gemma-3-1b-it-GGUF',
      isDownloaded: false,
    ),
     ModelMetadata(
      id: 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
      name: 'TinyLlama',
      description: "This repo contains GGUF format model files for TinyLlama's",
      sizeMB: 650.0,
      downloadUrl:
          'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q3_K_L.gguf?download=true',
      hfUrl: 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
      isDownloaded: false,
    ),
    ModelMetadata(
      id: 'microsoft/Phi-3-mini-4k-instruct-gguf',
      name: 'Microsoft/Phi-3', // display name with '/'
      description:
          'Phi-3 Mini 4K Instruct (3.8B) lightweight, strong reasoning.',
      sizeMB: 2400.0,
      downloadUrl:
          'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf?download=true',
      hfUrl:
          'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/tree/main',
      isDownloaded: false,
    ),
  ];

  List<ModelMetadata> get models => _models;

  /// On-disk filename convention: sanitize(displayName) + ".gguf"
  String fileNameFor(ModelMetadata m) => toGgufFileName(m.name);

  /// Back-compat: also check underscore variant
  List<String> _candidateFileNames(ModelMetadata m) {
    final normal = fileNameFor(m);
    final underscore = legacyUnderscoreVariant(normal);
    return {normal, underscore}.toList();
  }

  void markDownloaded(String id) {
    final i = _models.indexWhere((m) => m.id == id);
    if (i == -1 || _models[i].isDownloaded) return;
    _models = List<ModelMetadata>.from(_models)
      ..[i] = _models[i].copyWith(isDownloaded: true);
    notifyListeners();
  }

  void markUndownloaded(String id) {
    final i = _models.indexWhere((m) => m.id == id);
    if (i == -1 || !_models[i].isDownloaded) return;
    _models = List<ModelMetadata>.from(_models)
      ..[i] = _models[i].copyWith(isDownloaded: false);
    notifyListeners();
  }

  Future<void> checkIfModelDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final entries = await Directory(dir.path).list().toList();
    final existing = entries
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();

    bool changed = false;
    final next = <ModelMetadata>[];

    for (final m in _models) {
      final has = _candidateFileNames(m).any(existing.contains);
      if (m.isDownloaded != has) changed = true;
      next.add(m.copyWith(isDownloaded: has));
    }

    if (changed) {
      _models = next;
      notifyListeners();
    }
  }

  bool isModelDownloaded(String id) {
    final i = _models.indexWhere((m) => m.id == id);
    return i != -1 && _models[i].isDownloaded;
  }

  void setModels(List<ModelMetadata> next) {
    _models = next;
    notifyListeners();
  }
}
