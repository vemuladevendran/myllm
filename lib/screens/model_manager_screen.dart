import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/model_provider.dart';
import '../widgets/model_tile.dart';

class ModelManagerScreen extends StatelessWidget {
  const ModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final models = Provider.of<ModelProvider>(context).models;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Manager'),
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
