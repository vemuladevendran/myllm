import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/model_metadata.dart';

class ModelProvider with ChangeNotifier {
  final List<ModelMetadata> _models = [
    ModelMetadata(
      id: 'flyingfishinwater/Qwen3-4B-IQ4_NL',
      name: 'Qwen3-4B',
      description: 'Qwen3 is the latest generation of Qwen series. ',
      sizeMB: 650.0,
      downloadUrl:
          'https://huggingface.co/flyingfishinwater/good_and_small_models/resolve/main/Qwen3-4B-IQ4_NL.gguf?download=true',
      hfUrl: 'https://huggingface.co/Qwen/Qwen3-4B',
    ),
     ModelMetadata(
      id: 'fkrnkjfn',
      name: 'hello',
      description: 'checking model. ',
      sizeMB: 650.0,
      downloadUrl:
          'https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-UD-IQ1_M.gguf?download=true',
      hfUrl: 'checking model',
    ),

    ModelMetadata(
      id: 'stduhpf/google-gemma-3-1b-it-qat-q4_0-gguf-small',
      name: '1B model 2',
      description: 'stduhpf/google-gemma-3-1b-it-qat-q4_0-gguf-small ',
      sizeMB: 650.0,
      downloadUrl:
          'https://huggingface.co/stduhpf/google-gemma-3-1b-it-qat-q4_0-gguf-small/resolve/main/gemma-3-1b-it-q4_0_s.gguf?download=true',
      hfUrl: 'https://huggingface.co/stduhpf/google-gemma-3-1b-it-qat-q4_0-gguf-small',
    ),

  ];

  List<ModelMetadata> get models => _models;

  void markDownloaded(String id) {
    final model = _models.firstWhere((m) => m.id == id);
    model.isDownloaded = true;
    notifyListeners();
  }

  Future<void> checkIfModelDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    for (var model in _models) {
      final file = File('${dir.path}/${model.name.replaceAll(' ', '_')}.gguf');
      model.isDownloaded = await file.exists();
    }
    notifyListeners();
  }

  void markUndownloaded(String id) {
    final model = _models.firstWhere((m) => m.id == id);
    model.isDownloaded = false;
    notifyListeners();
  }
}
