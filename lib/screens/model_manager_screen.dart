import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/model_provider.dart';
import '../widgets/model_tile.dart';

class ModelManagerScreen extends StatelessWidget {
  const ModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelProvider>().models;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ModelProvider>().checkIfModelDownloaded();
            },
          )
        ],
      ),
      body: ListView.builder(
        itemCount: models.length,
        itemBuilder: (context, index) {
          return ModelTile(model: models[index]);
        },
      ),
    );
  }
}
