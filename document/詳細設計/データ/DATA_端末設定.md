# DATA：端末内設定（SharedPreferences 等）

最終更新: 2026-10-27  
上位: [README.md](./README.md)、S11／S16、IF  
実装: `ApiSettingsLocalDataSource`／`CustomLlmModelsLocalDataSource` 等

---

## 1. 保存場所

| 種類 | 用途 |
|------|------|
| SharedPreferences | ベースパス・LLM 接続・S16 UI・Dart SDK パス等 |

会話履歴はここに置かない（`coding_assist/` へ）。

---

## 2. ストレージ

| キー | 型 | 意味 |
|------|-----|------|
| `local_base_path` | string | ユーザー選択ベースフォルダ |
| `drive_app_root_folder_id` | string | ローカル時は `LMCode` ルート絶対パス |
| `storage_backend` | string | 過渡: `local` 等 |

---

## 3. 生成AI（llama.cpp）— 本アプリで使うキー

| キー | 型 | 既定／備考 |
|------|-----|------------|
| `local_llm_enabled` | bool | ローカルLLM使用 |
| `local_llm_host` | string | ホスト。既定 `127.0.0.1` 系 |
| `local_llm_port` | int | 既定 `8080` |
| `local_llm_coding_model_id` | string | **コーディング用** 組み込み ID |
| `local_llm_coding_custom_model_id` / `_label` / `_gguf_file` | string | コーディング用カスタム |
| `local_llm_coding_context_size` | int | 既定 **131072（128k）**。UI 上限 262144（256k） |
| `local_llm_coding_thinking_enabled` | bool | 既定 false |
| `local_llm_coding_auto_apply_patches` | bool | S16「Agent自動実行」。既定 **false** |
| `coding_ui_font_menu` | double | S16 メニュー部。既定 **12**（10〜22） |
| `coding_ui_font_editor` | double | S16 エディタ部。既定 **13** |
| `coding_ui_font_agent` | double | S16 Agent 部。既定 **13** |
| `app_theme_mode` | string | 外観。`system`／`light`／`dark`。既定 **system**。実装: `AppThemeController` |
| `app_color_overrides_light` | string (JSON) | ライト配色の上書き。`{ tokenId: ARGB int }`。空／欠落＝既定。実装: `AppThemeController` |
| `app_color_overrides_dark` | string (JSON) | ダーク配色の上書き（同上） |
| `dart_sdk_path` | string | 空＝PATH から `dart` 探索。正本: S11 §4.6 |
| `custom_llm_models_json` | string (JSON) | S11a 登録一覧 |

### 3.1 互換残置（本アプリでは主に使わない）

サーバー解決は **コーディング用のみ**（`forServer()` 相当）。

---

## 4. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-27 | `app_color_overrides_light`／`_dark`（個別色カスタム）を追加 |
| 2026-10-27 | `app_theme_mode`（ライト／ダーク／システム）を追加 |
| 2026-10-27 | lmcode 切り出し。コーディング用キーを正として整理 |
