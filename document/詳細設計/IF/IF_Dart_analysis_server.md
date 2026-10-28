# IF：Dart Analysis Server（S16 入力中補完）

最終更新: 2026-10-15  
上位: [README.md](./README.md)、[S16_コーディングアシスト.md](../画面/S16_コーディングアシスト.md) §2.2.7、[S11_エンジン設定.md](../画面/S11_エンジン設定.md) §4.6  
データ: [DATA_端末設定.md](../データ/DATA_端末設定.md)（`dart_sdk_path`）

**状態: 実装済（初版）** — `lib/features/coding_assist/data/dart_analysis_server_client.dart` 等

---

## 1. 目的と位置づけ

| 項目 | 内容 |
|------|------|
| 役割 | S16 エディタの **Dart 入力中補完**（メンバ／変数等）。LLM インライン提案ではない |
| 必須度 | **任意**。未設定・起動失敗でも S16 の Agent／編集は継続（補完のみ OFF） |
| ランタイム | 端末の **Flutter／Dart SDK** 付属の Analysis Server（LSP） |
| 同梱 | **しない**（S11 でパス指定、または PATH 探索） |
| 通信 | 子プロセスの **stdio LSP**（HTTP ポートは使わない） |

---

## 2. コンポーネント

```text
[S11] dart_sdk_path（空＝PATH）
        │
[S16] WS オープン
        ▼
  DartSdkResolver ──► dart 実行ファイル
        │
        ▼ Process（stdio）
  dart language-server
        ▲
  CodingDartLspClient（目標名・実装裁量）
        │ textDocument/completion 等
        ▼
  re_editor 候補 UI
```

| 論理名 | 責務 |
|--------|------|
| `DartSdkResolver`（目標） | S11 パスまたは PATH から `dart` を解決 |
| LSP クライアント（目標） | initialize／document sync／completion。補完以外は最小 |
| Analysis Server | `dart language-server`（公式 LSP 入口） |
| エディタ橋渡し | **推奨確定**: キャッシュ＋デバウンス＋再 show。`CodeAutocompletePromptsBuilder.build` は同期のままキャッシュを返す（S16 §2.2.7） |

---

## 3. SDK パス（S11）

| 項目 | 方針 |
|------|------|
| 設定 | S11「Dart／Flutter SDK パス」。キー `dart_sdk_path` |
| 空欄 | `PATH` 上の `dart`（`which dart` 相当）を探索 |
| 解決失敗 | サーバー起動しない。S16 ステータスで案内 |
| llama | **無関係**。パス変更で `llama-server` は再起動しない |

---

## 4. 起動・停止

| 項目 | 方針 |
|------|------|
| 起動契機 | **S16 でワークスペース（プロジェクトフォルダ）をオープンしたとき** |
| 作業ディレクトリ | WS ルート（`rootUri`／workspaceFolders に渡す） |
| コマンド例 | `{dart} language-server`（引数は実装で公式に合わせる） |
| 停止 | WS 閉じ／S16 離脱／アプリ終了。SDK パス変更時は開いている WS があれば再起動可 |
| 失敗 | 補完 OFF。アプリ本体は落とさない |

WS に `.dart` が無くても、オープン時起動でよい（アイドルコスト許容。問題なら後続で遅延起動を検討）。

---

## 5. プロトコル（最小）

本段で必須とする LSP 範囲:

| 操作 | 用途 |
|------|------|
| initialize／initialized | 能力交渉 |
| textDocument/didOpen／didChange／didClose | 未保存タブは **タブ内容を正**（S16 方針） |
| textDocument/completion | 候補取得 |
| textDocument/definition | 選択した識別子の宣言範囲（吹き出し表示） |

定義の画面遷移・診断の本格 UI・formatting は当面対象外（定義は吹き出しにだけ出す）。

---

## 6. 失敗時

| 状況 | 挙動 |
|------|------|
| SDK 未検出 | 補完 OFF＋案内（S11 へ誘導してよい） |
| プロセス即終了 | 同上。S12 記録は任意 |
| completion タイムアウト | その回は候補なし。エディタ操作は継続 |

---

## 7. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-16 | 定義表示は textDocument/definition の宣言範囲を吹き出しへ。documentSymbol のメンバ一覧は撤回 |
| 2026-10-15 | 初版。S11 パス・WS オープン時起動・stdio LSP・補完最小範囲 |
