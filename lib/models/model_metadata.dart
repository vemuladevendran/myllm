class ModelMetadata {
  final String id;
  final String name;
  final String description;
  final double sizeMB;
  final String downloadUrl; // direct file download
  final String hfUrl;       // model card page
  bool isDownloaded;

  ModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeMB,
    required this.downloadUrl,
    required this.hfUrl,
    this.isDownloaded = false,
  });
}
