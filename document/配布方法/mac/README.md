# LMCode（macOS）配布・セットアップメモ

最終更新: 2026-10-27  
対象: **コーディングアシスト（S16）**。会議／ASR／仮想マイクは本アプリ対象外。

---

## 内容物（詰め込むこと）

```text
LMCode
└── local_llm
    └── models
        ├── （ユーザーが追加する .gguf）
        ├── gemma-4-12b-it-Q4_0.gguf          … MTP 用の本体（任意例）
        └── mtp-gemma-4-12b-it-Q8_0.gguf      … MTP の下書き係（任意。一覧には出ない）
```

アプリ本体（`.app`）と、必要なら同梱の `llama-server` バイナリは配布形態に従う。  
**GGUF は同梱しない**（ライセンスは利用者責任）。S11a で取り込むか、上記 `models/` に置く。

---

## 配置場所

### LMCode をそのまま移動する

移動先例: `/Users/<PC名>/Documents/`

初回起動でベース配下に `LMCode/` が作られる実装でも可（基本設計 `03_データ設計.md`）。

---

## 重要

* ollama との共存不可のため、停止する（`llama-server` を使用するため）。アンインストールは不要。止まっていれば OK。
* マイク／画面収録／仮想マイク（BlackHole）は **本アプリでは不要**。

---

## llama.cpp サーバー

```bash
brew install llama.cpp
```

Gemma 4 の MTP（下書き係）を使うときは、`gemma4-assistant` を読める版が必要。古いと 12B 起動に失敗する。

```bash
brew upgrade llama.cpp
```

アプリ同梱の `llama-server` を使う場合は brew 版とポートがぶつからないよう注意（既定 8080）。

---

## MTP（Gemma 4 12B の下書き係）

任意。コーディング用の 12B を速くする。

### 取得

https://huggingface.co/unsloth/gemma-4-12b-it-GGUF

次の2つ。ファイル名は変えない（量子化名を外した系統が一致するときだけ併用する）。

* `gemma-4-12b-it-Q4_0.gguf`（本体）
* `MTP/mtp-gemma-4-12b-it-Q8_0.gguf`（下書き係）

QAT 版（ファイル名に `qat`）とは組にしない。

### 配置

両方を `LMCode/local_llm/models/` に置く。アプリの「モデルを追加」から取り込んでも同じ場所にコピーされる。

下書き係はモデル一覧に出ない。コーディング用モデルは本体を選ぶ。

### 確認

S16 を開き直す。状態表示が次なら併用中。

* モデル名の横に `MTP`
* 進行欄に `MTP 下書き係を併用します（…）`

---

## 再起動

モデル配置や brew 更新後はアプリを再起動する。

---

## ビルド方法

* Xcode でアーカイブ
* カスタム Distribution でビルド

詳細方針は `document/基本設計/05_運用配布保守.md`。
