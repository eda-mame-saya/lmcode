# 詳細設計：IF

最終更新: 2026-10-27

アプリ（Flutter）と外部／サイドカーとの **契約** をここに置く。  
上位: `../00_概要と読み方.md`、`document/基本設計/01_システム構成.md`。

---

## 1. 文書一覧

| ファイル | 接続先 | 位置づけ |
|----------|--------|----------|
| [IF_LLM_llama_server.md](./IF_LLM_llama_server.md) | llama.cpp `llama-server` | **必須**（生成AI ON・Agent 時） |
| [IF_Dart_analysis_server.md](./IF_Dart_analysis_server.md) | Dart Analysis Server（LSP） | **任意**（S16 Dart 入力中補完） |
| [IF_SourceKit_LSP.md](./IF_SourceKit_LSP.md) | SourceKit-LSP ＋ Xcode 索引 BSP | **任意**（S16 Swift 補完・定義） |

---

## 2. 決定サマリ

| 項目 | 決定 |
|------|------|
| LLM API | OpenAI 互換 `/v1`。認証なし。`127.0.0.1` のみ |
| LLM 起動 | アプリ起動時（生成AI ON）。モデルは **コーディング用のみ** |
| stream | S16＝ON |
| ポート | 既定 8080。衝突時は固定のみ（失敗表示＋手動変更） |
| S11 接続 | LLM ベースURL＋ポート。**Dart SDK パス**は S11 §4.6 |
| Dart LS | S16。**WS オープン時**起動・stdio LSP |
| SourceKit-LSP | S16 Swift。stdio LSP。Xcode は BSP。S11 パス欄は作らない |

---

## 3. 既定接続先

| 対象 | 既定 |
|------|------|
| llama-server | `http://127.0.0.1:8080` |
| Dart Analysis Server | stdio。SDK は S11 `dart_sdk_path` または PATH |
| SourceKit-LSP | stdio。toolchain は `xcode-select -p` |

---

## 4. 関連画面

| 画面 | 関係 |
|------|------|
| S11 | LLM ベースURL・ポート・モデル・ctx・thinking・**Dart SDK パス** |
| S16 | Agent（LLM stream）。Dart LS／SourceKit |

---

## 5. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-27 | lmcode 切り出し。LLM／Dart／SourceKit のみに整理 |
