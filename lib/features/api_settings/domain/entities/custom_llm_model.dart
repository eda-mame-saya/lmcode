/// ユーザーが取り込んだ GGUF モデルの登録情報。
class CustomLlmModel {
  const CustomLlmModel({
    required this.id,
    required this.label,
    required this.ggufFileName,
    required this.addedAtMs,
  });

  final String id;
  final String label;
  final String ggufFileName;
  final int addedAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'ggufFileName': ggufFileName,
        'addedAtMs': addedAtMs,
      };

  factory CustomLlmModel.fromJson(Map<String, dynamic> json) {
    return CustomLlmModel(
      id: (json['id'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
      ggufFileName: (json['ggufFileName'] as String? ?? '').trim(),
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
