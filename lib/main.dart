import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'layout/shell.dart';
import 'state/model_provider.dart';
import 'services/model_downloader.dart';

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ModelProvider()..checkIfModelDownloaded(),
        ),
        ChangeNotifierProxyProvider<ModelProvider, DownloadManager>(
          create: (_) => DownloadManager(),
          update: (_, modelProvider, downloader) {
            downloader ??= DownloadManager();
            downloader.attach(modelProvider);
            return downloader;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Chat with Local LLM',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        home: const Shell(),
      ),
    );
  }
}
