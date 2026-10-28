import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../generative_ai/data/local_llm_runtime_paths.dart';
import '../../domain/entities/custom_llm_model.dart';

/// ユーザー取り込み GGUF の登録・配置。
class CustomLlmModelsLocalDataSource {
  CustomLlmModelsLocalDataSource({required SharedPreferences preferences})
      : _preferences = preferences;

  final SharedPreferences _preferences;

  static const _prefKey = 'custom_llm_models_json';

  Future<List<CustomLlmModel>> list() async {
    final raw = _preferences.getString(_prefKey)?.trim() ?? '';
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => CustomLlmModel.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => m.id.isNotEmpty && m.ggufFileName.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveAll(List<CustomLlmModel> models) async {
    await _preferences.setString(
      _prefKey,
      jsonEncode(models.map((e) => e.toJson()).toList()),
    );
  }

  /// GGUF を models へコピーして登録する。
  Future<CustomLlmModel> importGguf({
    required String sourcePath,
    required String label,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('ファイルが見つかりません');
    }
    final lower = sourcePath.toLowerCase();
    if (!lower.endsWith('.gguf')) {
      throw StateError('GGUF ファイルのみ取り込めます');
    }

    final root = await LocalLlmRuntimePaths.resolveInstalledRoot();
    if (root == null) {
      throw StateError('モデル保存先を解決できませんでした');
    }
    final modelsDir = Directory(LocalLlmRuntimePaths.modelsDirUnder(root));
    await modelsDir.create(recursive: true);

    final baseName = p.basename(sourcePath);
    var destName = baseName;
    var dest = File(p.join(modelsDir.path, destName));
    if (await dest.exists() &&
        p.normalize(dest.absolute.path) !=
            p.normalize(source.absolute.path)) {
      final stem = p.basenameWithoutExtension(baseName);
      destName = '${stem}_${DateTime.now().millisecondsSinceEpoch}.gguf';
      dest = File(p.join(modelsDir.path, destName));
    }
    if (p.normalize(dest.absolute.path) !=
        p.normalize(source.absolute.path)) {
      await source.copy(dest.path);
    }

    final model = CustomLlmModel(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: label.trim().isEmpty
          ? p.basenameWithoutExtension(destName)
          : label.trim(),
      ggufFileName: destName,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final all = await list();
    await _saveAll([...all, model]);
    return model;
  }

  Future<void> remove(String id) async {
    final all = await list();
    await _saveAll(all.where((m) => m.id != id).toList());
  }
}
