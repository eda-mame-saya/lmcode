# IF：SourceKit-LSP（S16 Swift 入力中補完・定義表示）

最終更新: 2026-10-16  
上位: [README.md](./README.md)、[S16_コーディングアシスト.md](../画面/S16_コーディングアシスト.md) §2.2.8

**状態: 実装済（初版）** — S16。Xcode プロジェクトは `showBuildSettingsForIndex` ＋ BSP。定義 range が 1 点のときは宣言の終わりまで広げる

---

## 1. 目的と位置づけ

| 項目 | 内容 |
|------|------|
| 役割 | S16 エディタの **Swift 入力中補完**と、選択識別子の **定義吹き出し**。LLM インライン提案ではない |
| 必須度 | **任意**。未検出・起動失敗でも S16 の Agent／編集は継続（Swift 補完と定義だけ OFF） |
| ランタイム | 端末の **Xcode** 付属 `sourcekit-lsp`。アプリ同梱しない |
| 通信 | 子プロセスの **stdio LSP**。プロジェクト情報は別子プロセスの **stdio BSP** |
| S11 | **パス欄は足さない**。`xcode-select -p` が指す Xcode の toolchain を使う |

---

## 2. コンポーネント

```text
[S16] WS オープン（直下に .xcodeproj が1つ、スキームが1つ）
        │
        ├─ xcodebuild -showBuildSettingsForIndex
        │     → ファイルごとの swiftASTCommandArguments
        │
        ▼ アプリが WS ルートへ buildServer.json を書く
  BSP 子プロセス  ◄── sourcekit-lsp が argv で起動
        │ textDocument/sourceKitOptions
        ▼
  sourcekit-lsp（stdio LSP）
        │ completion / definition
        ▼
  re_editor 候補 UI／定義吹き出し
```

| 論理名 | 責務 |
|--------|------|
| toolchain 解決 | `xcode-select -p` ＋ `Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp` と、同じ Developer の `xcodebuild` |
| 索引設定 | `xcodebuild -project <proj> -scheme <scheme> -destination 'platform=macOS,arch=arm64' -showBuildSettingsForIndex` |
| BSP | 索引設定の `swiftASTCommandArguments` を `compilerArguments` として返す |
| LSP クライアント | initialize／document sync／completion／definition。未保存タブを正にする |
| エディタ橋渡し | Dart 補完と同じキャッシュ＋デバウンス（S16 §2.2.7） |

---

## 3. 起動条件

| 条件 | 挙動 |
|------|------|
| WS 直下の `.xcodeproj` が1つ、`xcodebuild -list` のスキームが1つ | BSP ＋ `sourcekit-lsp` を起動 |
| スキームが 0 または複数 | Swift 補完オフ＋ステータス。選択 UI は本段では作らない |
| ルートに `Package.swift` があり `.xcodeproj` が無い | BSP なしで `sourcekit-lsp` のみ（SwiftPM はサーバが索引する。確認済） |
| Flutter ルートの `ios/*.xcodeproj` だけ | **起動しない**（本段の対象外） |
| `sourcekit-lsp` が Command Line Tools しか無い等で未検出 | Swift 補完オフ＋案内 |

WS を閉じる／S16 を離れる／アプリ終了で、`sourcekit-lsp` と BSP を止める。**アプリが書いた `buildServer.json` だけ削除**する。もともとあったファイルは上書きも削除もしない。

---

## 4. LSP（最小）

| 操作 | 用途 |
|------|------|
| initialize／initialized | 能力交渉。completion はスニペットなし。definition は `linkSupport: true` |
| textDocument/didOpen／didChange／didClose | `languageId` は `swift`。未保存タブの全文を正とする |
| textDocument/completion | 候補 |
| textDocument/definition | 選択識別子の位置 |

定義の画面遷移・診断 UI・formatting は対象外。

---

## 5. BSP（Xcode プロジェクトで必須）

`sourcekit-lsp` は `.xcodeproj` を単独では読まない。`buildServer.json` が WS ルートにあり、起動した BSP が次を満たすこと。

`build/initialize` の結果:

| フィールド | 値 |
|------------|----|
| `dataKind` | `sourceKit` |
| `data.sourceKitOptionsProvider` | `true` |

このフラグが無いと、SourceKit-LSP は単一ファイル用のフォールバック引数（`-sdk` とそのファイルだけ）のままになる。別ファイルの定義は空になる（確認済）。

| 操作 | 返すもの |
|------|----------|
| `workspace/buildTargets` | スキームに対応するターゲット 1 つ |
| `buildTarget/sources` | 索引設定に含まれる `.swift` |
| `textDocument/sourceKitOptions` | そのファイルの `swiftASTCommandArguments` を `compilerArguments`、作業ディレクトリは WS ルート |

確認時の実応答（Xcode 26.1.1、スキーム `sampleaaaaa`）: `sampleaaaaaApp.swift` の `ContentView()` から `textDocument/definition` が `ContentView.swift` の `struct ContentView` の名前位置を返した。範囲は開始と終了が同じ 1 点で、宣言全体ではない。

---

## 6. 定義範囲の扱い

吹き出し用の抜粋は、返った range の開始行から切る。開始と終了が同じ点のときは、その行の宣言から対応する `}` まで広げる。点でない range はその範囲を使う。

---

## 7. 失敗時

| 状況 | 挙動 |
|------|------|
| `sourcekit-lsp` 未検出 | Swift 補完オフ＋案内 |
| `xcodebuild` 失敗／索引設定が空 | 同上。編集は継続 |
| completion／definition のタイムアウト | その回は候補なし、または「定義が見つかりません」 |

---

## 8. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-16 | 初版実装。起動条件・BSP・定義範囲は設計どおり |
