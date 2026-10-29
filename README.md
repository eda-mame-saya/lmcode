# LMCode

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

ローカル LLM で動く **デスクトップ向けコーディングアシスト**（Flutter）。  
クラウドにソースを送らず、端末上の `llama-server`（llama.cpp）と GGUF モデルで Agent・編集・ターミナルを使えます。

```text
起動（S16）
  左: フォルダ／検索／Git
  中央: エディタ ＋ ターミナル
  右: Agent
        └→ エンジン設定（S11）→ モデル追加（S11a）
```

| 項目 | 内容 |
|------|------|
| 対象 OS | **macOS**／**Windows**（起動画面はコーディングアシスト S16） |
| 生成 AI | **llama.cpp のみ**（Ollama／クラウド LLM は正としない） |
| モデル | **GGUF は同梱しない**。利用者が追加（ライセンスは利用者責任） |
| ログイン | 不要（完全ローカル） |

---

## できること

- プロジェクトフォルダを開いてツリー閲覧・編集・保存
- 右ペイン Agent による複数ファイルの読取・変更案（パッチ適用／却下）
- 内蔵ターミナル（ワークスペースルートが cwd）
- ワークスペース種別の自動判定（Flutter／Xcode・Swift／React／Android／Python／汎用）
- Dart 入力中補完（Flutter／Dart SDK）、Swift 入力中補完・定義（macOS＋Xcode）
- Flutter ワークスペースでは Agent 自動実行時に analyze／test の自動検証（最大 3 セット）

詳細な画面仕様は [`document/詳細設計/画面/S16_コーディングアシスト.md`](document/詳細設計/画面/S16_コーディングアシスト.md) を参照してください。

---

## 動作環境（目安）

| 項目 | 推奨 |
|------|------|
| OS | macOS または Windows 10/11（64bit） |
| メモリ | **32GB 以上**（14B 級 GGUF・128k ctx 想定） |
| ディスク | アプリ＋ユーザー用意の GGUF 分 |
| ネット | 本体の Agent／編集はオフライン可（モデル取得時のみ必要） |
| 開発ツール | [Flutter](https://docs.flutter.dev/get-started/install) stable（SDK 制約: Dart `^3.11.0`） |
| LLM ランタイム | `llama-server`（Homebrew の llama.cpp、または `~/Documents/LMCode/local_llm/` へ配置） |

---

## クイックスタート（macOS・ソースから起動）

### 1. 前提インストール

```bash
# Flutter（PATH に flutter があること）
flutter doctor

# デスクトップ有効化
flutter config --enable-macos-desktop

# llama-server（Agent 利用時）
brew install llama.cpp
# 古い場合は upgrade（Gemma 4 MTP 等で必要になることがある）
# brew upgrade llama.cpp
```

`flutter doctor` で macOS 向けに Xcode／CocoaPods 等が通っていることを確認してください。

### 2. 取得と依存解決

```bash
git clone <このリポジトリの URL>
cd lmcode
flutter pub get
```

### 3. 起動

```bash
flutter run -d macos
```

デバッグ起動でも、初回は **GGUF の追加** が必要です（次節）。

### 4. リリースビルド（任意）

```bash
flutter build macos --release
```

成果物は概ね次の場所です。

```text
build/macos/Build/Products/Release/lmcode.app
```

署名・公証・社内配布の実務は [`document/配布方法/mac/README.md`](document/配布方法/mac/README.md) と [`document/基本設計/05_運用配布保守.md`](document/基本設計/05_運用配布保守.md) を参照してください。

---

## 初回セットアップ（ローカル LLM）

アプリは **GGUF を同梱しません**。Agent を使う前にモデルを用意してください。

### 1. `llama-server` の配置

探索順の例（先頭から存在するものを使用）:

1. `~/Documents/LMCode/local_llm/llama-server`
2. 実行ファイル近傍の `local_llm/llama-server`
3. Homebrew: `/opt/homebrew/bin/llama-server` または `/usr/local/bin/llama-server`
4. `PATH` 上の `llama-server`

開発時は `brew install llama.cpp` が手早いです。  
既定ポートは **8080** です。**Ollama が動いているとポートがぶつかる**ことがあるため、利用時は Ollama を止めてください（アンインストールは不要）。

### 2. GGUF の追加

1. アプリを起動する（S16）
2. エンジン設定（S11）を開く
3. **モデルを追加…**（S11a）からローカルの `.gguf` を取り込む  
   - コピー先: `~/Documents/LMCode/local_llm/models/`
4. **コーディング用モデル**とコンテキスト長（既定 **131072 / 128k**、最大 256k）を選んで保存

手入力のモデル ID や URL からの pull はしません。ローカルファイル選択のみです。

#### モデルの目安

- コーディング用途は **14B 級以上**の GGUF を想定
- 例（任意）: [unsloth/gemma-4-12b-it-GGUF](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF)  
  - MTP（下書き係）を使う場合の配置メモは [`document/配布方法/mac/README.md`](document/配布方法/mac/README.md)

**モデルのライセンス・利用条件はダウンロード元に従い、利用者自身が確認・遵守してください。**

### 3. （任意）Dart／Flutter SDK パス

Dart 入力中補完を使う場合、エンジン設定（S11）で SDK パスを指定できます。空欄なら `PATH` から `dart` を探索します。

---

## 使い方（最短）

1. アプリ起動 → **フォルダを開く**（Flutter 以外のプロジェクトも可）
2. 中央エディタで閲覧・手編集。下部でターミナル（必要なら）
3. 右の Agent に依頼を書く  
   - 自動実行 OFF: 変更案は適用／却下を人手で行う（新規ファイルは作成承認）  
   - 自動実行 ON: Update／Add を自動適用。Flutter では続けて analyze／test
4. モデルやポートの変更は **エンジン設定** → 保存（llama-server 再起動）

推奨ウィンドウ目安: 幅 1280 × 高さ 800 以上。

---

## データの置き場所

```text
~/Documents/LMCode/
├── local_llm/
│   └── models/          … 取り込んだ GGUF
└── coding_assist/       … 会話・ワークスペースメタなど
```

ソースの正本は、S16 で開いた **ユーザーのプロジェクトフォルダ** 側です。  
アンインストールしても上記 `LMCode/` やワークスペースは自動では消しません。

---

## Windows（ソースから起動）

前提: Visual Studio 2022（または対応版）＋「C++ によるデスクトップ開発」。  
ビルドは **Windows 実機必須**（クロスビルド不可）。

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
flutter build windows --release
```

`llama-server.exe` は `%USERPROFILE%\Documents\LMCode\local_llm\` または exe 隣の `local_llm\` へ配置。  
Swift 補完は macOS のみ。Dart 補完・Agent・ターミナル・RAM 表示は Windows でも利用可。

方針: [`document/基本設計/08_Windows対応_実装方針.md`](document/基本設計/08_Windows対応_実装方針.md)  
配布: [`document/配布方法/windows/`](document/配布方法/windows/)

---

## トラブルシュート

| 症状 | 確認すること |
|------|----------------|
| Agent が送れない／応答しない | ローカル LLM ON、GGUF 追加済み、`llama-server` 起動、ポート 8080、Ollama 停止 |
| `llama-server` が見つからない | `brew install llama.cpp`、または `~/Documents/LMCode/local_llm/llama-server` に配置 |
| モデル追加後も一覧に出ない | アプリ再起動。MTP 下書き係（`mtp-*.gguf`）は一覧に出ない仕様 |
| Dart 補完が出ない | S11 の SDK パス、または `which dart`／Flutter SDK |
| Windows で `llama-server` が見つからない | `%USERPROFILE%\Documents\LMCode\local_llm\llama-server.exe` を配置 |

---

## リポジトリ構成（抜粋）

```text
lmcode/
├── lib/                 … Flutter アプリ本体
│   └── features/
│       ├── coding_assist/   … S16
│       ├── api_settings/    … S11／S11a
│       └── generative_ai/   … llama-server 起動・クライアント
├── macos/ / windows/    … デスクトップランナー
├── document/            … 設計・配布ドキュメント（正本）
└── pubspec.yaml
```

### 設計ドキュメント

矛盾がある場合は実装を正とし、設計は追随します。読む順番の目安:

| 優先 | パス | 用途 |
|------|------|------|
| 1 | [`document/基本設計/00_概要とスコープ.md`](document/基本設計/00_概要とスコープ.md) | スコープ |
| 2 | [`document/詳細設計/画面/00_画面一覧と遷移.md`](document/詳細設計/画面/00_画面一覧と遷移.md) | 画面マップ |
| 3 | [`document/詳細設計/画面/S16_コーディングアシスト.md`](document/詳細設計/画面/S16_コーディングアシスト.md) | 主機能 |
| 4 | [`document/詳細設計/画面/S11_エンジン設定.md`](document/詳細設計/画面/S11_エンジン設定.md) | LLM／SDK 設定 |
| — | [`document/配布方法/`](document/配布方法/) | mac／Windows 配布メモ |

---

## 開発コマンド

```bash
flutter pub get
flutter analyze
flutter run -d macos
flutter build macos --release
```

---

## ライセンス・注意

本ソフトウェアは **[Apache License 2.0](LICENSE)** の下で公開しています。  
著作権表示は [`NOTICE`](NOTICE) を参照してください。

```text
Copyright 2026 The LMCode Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

- アプリ内の **設定 → OSSライセンス**（またはエンジン設定の同ボタン）で、依存パッケージとサイドカー（llama.cpp）の条文も確認できます。
- 本リポジトリに **GGUF モデルは含まれません**。モデルの権利・利用条件は各配布元に従ってください。
- 生成 AI は **localhost の llama-server** を前提とします。外部公開しないでください。

---

## 貢献・フィードバック

Issue／Pull Request は歓迎です。特に断りがなければ、投稿は **Apache-2.0** の下で本プロジェクトにライセンスされるものとします（ライセンス本文 §5）。  
大きな仕様変更は `document/基本設計/` と該当の画面設計（S11／S16）と整合させてください。
