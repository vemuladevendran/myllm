import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/model_metadata.dart';

class ModelProvider with ChangeNotifier {
  final List<ModelMetadata> _models = [
    ModelMetadata(
      id: 'tinyllama/TinyLlama-1.1B-Chat-v1.0',
      name: 'TinyLlama',
      description: 'A small 1.1B chat model',
      sizeMB: 450.0,
      downloadUrl: 'https://huggingface.co/jartine/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      hfUrl: 'https://huggingface.co/jartine/TinyLlama-1.1B-Chat-v1.0-GGUF',
    ),
    ModelMetadata(
      id: 'TheBloke/Mistral-7B-Instruct-v0.1-GGUF',
      name: 'Mistral 7B',
      description: 'Quantized 7B instruct model',
      sizeMB: 700.0,
      downloadUrl: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
      hfUrl: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF',
    ),
    ModelMetadata(
      id: 'bartowski/gemma-2-2b-it-GGUF',
      name: 'Gemma 2B',
      description: 'Instruction tuned model by Google',
      sizeMB: 550.0,
      downloadUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q6_K.gguf',
      hfUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF',
    ),
    ModelMetadata(
      id: 'TheBloke/phi-2-GGUF',
      name: 'Phi-2',
      description: 'Compact model for reasoning tasks',
      sizeMB: 300.0,
      downloadUrl: 'https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf',
      hfUrl: 'https://huggingface.co/TheBloke/phi-2-GGUF',
    ),
    ModelMetadata(
      id: 'flyingfishinwater/Qwen3-4B-IQ4_NL',
      name: 'Qwen3-4B',
      description: 'Qwen3 is the latest generation of Qwen series. ',
      sizeMB: 650.0,
      downloadUrl: 'https://huggingface.co/flyingfishinwater/good_and_small_models/resolve/main/Qwen3-4B-IQ4_NL.gguf?download=true',
      hfUrl: 'https://huggingface.co/Qwen/Qwen3-4B',
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
}
