class ModelMetadata {
  final String id;
  final String name;          // DISPLAY NAME (may include '/')
  final String description;
  final double sizeMB;
  final String downloadUrl;
  final String hfUrl;
  final bool isDownloaded;

  const ModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeMB,
    required this.downloadUrl,
    required this.hfUrl,
    required this.isDownloaded,
  });

  ModelMetadata copyWith({
    String? id,
    String? name,
    String? description,
    double? sizeMB,
    String? downloadUrl,
    String? hfUrl,
    bool? isDownloaded,
  }) {
    return ModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      sizeMB: sizeMB ?? this.sizeMB,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      hfUrl: hfUrl ?? this.hfUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}
