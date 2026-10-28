# 詳細設計：データ

最終更新: 2026-10-27

ローカルフォルダ・JSON・端末設定の **実装形** をここに置く。  
上位: `../00_概要と読み方.md`、`document/基本設計/03_データ設計.md`。

ファイル名・JSON 形は **現行実装を正本**として文書化する。

---

## 1. 文書一覧

| ファイル | 内容 |
|----------|------|
| [DATA_フォルダ規約.md](./DATA_フォルダ規約.md) | `LMCode/` ツリー・システム除外 |
| [DATA_コーディングアシスト.md](./DATA_コーディングアシスト.md) | `LMCode/coding_assist/`（S16） |
| [DATA_端末設定.md](./DATA_端末設定.md) | SharedPreferences 等 |

---

## 2. 決定サマリ

| 項目 | 決定 |
|------|------|
| ソース正本 | ユーザーが開いたワークスペース |
| S16 履歴 | `LMCode/coding_assist/`（システム扱い） |
| 会話にソース全文を蓄積しない | tool 要約・截断可。詳細は DATA_コーディングアシスト |

---

## 3. 実装参照（入口）

| 領域 | 主な正本 |
|------|----------|
| コーディングアシスト | `lib/features/coding_assist/` |
| 接続設定 | `lib/features/api_settings/` |
| システムフォルダ | `lib/features/drive/domain/drive_system_folders.dart`（`local_llm`／`coding_assist` 等） |

---

## 4. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-27 | lmcode 切り出し。coding_assist／端末設定／フォルダ規約のみ |
