// lib/services/file_naming.dart
// Keep display names intact; only sanitize when creating on-disk filenames.

String sanitizeFileName(String name) {
  final bad = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
  final cleaned = name.replaceAll(bad, '_').trim();
  return cleaned.isEmpty ? 'model' : cleaned;
}

/// Display name -> on-disk .gguf file name (sanitized)
String toGgufFileName(String displayName) {
  final base = sanitizeFileName(displayName);
  return base.toLowerCase().endsWith('.gguf') ? base : '$base.gguf';
}

/// Legacy (spaces -> underscores) used when scanning/deleting.
String legacyUnderscoreVariant(String fileName) {
  return fileName.replaceAll(' ', '_');
}
