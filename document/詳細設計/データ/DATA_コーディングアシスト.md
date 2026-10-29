# DATA：コーディングアシスト（S16）

最終更新: 2026-10-29  
**状態: MVP＋実用（一部）実装済**（会話はセッションのみ。直近ワークスペースとフォルダ展開だけ `index.json`）  
上位: [README.md](./README.md)、[S16_コーディングアシスト.md](../画面/S16_コーディングアシスト.md)、[IF_LLM_llama_server.md](../IF/IF_LLM_llama_server.md)  
実装: `lib/features/coding_assist/`

本アプリ（LMCode）の永続データは本系統が主。**会話はディスクに書かない。**  
Git 操作（branch 表示・add・commit）は **ワークスペース側の `.git`** を対象とし、本フォルダにはコミット履歴を保存しない。  
ソース正本のルートは **S16 でユーザーが開いたワークスペース**（相対パスの基準）。`coding_assist/` 配下ではない。  
**ワークスペース種別**（`CodingWorkspaceKind`）は走査時に再判定する（S16 §4.1a）。  
**コンテキスト圧縮**は API 送信ビューのみ（S16 §5.7）。会話を閉じると消える。  
**送信前の開いているファイル取り込み**（`CodingAttachedOpenFile`）および **選択範囲付与**はセッション UI 状態のみ。  
**Markdown／マークアップ ビュー**（S16 §2.2.5）はセッション UI 状態のみ（永続しない）。

---

## 1. 置き場

| 項目 | 内容 |
|------|------|
| ルート | `~/Documents/LMCode/coding_assist/`（ベースフォルダ設定は使わない） |
| 扱い | **システムフォルダ**（プロジェクト一覧・新規名から除外） |
| 予約名 | `DriveSystemFolders.codingAssist`（`coding_assist`）案 |
| ソース正本 | ユーザーが開いたワークスペースフォルダ（任意パス） |

```text
LMCode/coding_assist/
└── index.json    … 直近ワークスペースとフォルダ展開。会話は含まない
```

---

## 2. 保存する項目

### 2.1 スレッド（会話）

保存しない。開いているあいだのメモリだけ。

### 2.2 ワークスペース meta

| 項目 | 必須 | 備考 |
|------|------|------|
| id | ○ | パスの安定ハッシュ等 |
| rootPath | ○ | 絶対パス |
| displayName | ○ | フォルダ名 |
| lastOpenedAt | ○ | |
| excludeRulesVersion | △ | 既定除外セットの版 |
| workspaceKind | △ | 任意。`flutter`／`swiftXcode`／`react`／`android`／`python`／`generic`。永続しなくても走査時に再判定可（`CodingWorkspaceKind`）。Agent system 切替の根拠（判定は S16 §4.1a） |

#### 2.2.1 workspaceKind の値

| 値 | 意味 |
|----|------|
| `flutter` | `pubspec.yaml` あり（第一ターゲット） |
| `swiftXcode` | Xcode／Swift／SPM 系 |
| `react` | React／Next／Vite 等（`package.json`＋JSX/TSX 等） |
| `android` | Android（Java／Kotlin）。`settings.gradle(.kts)`／`AndroidManifest.xml` 等 |
| `python` | Python パッケージ／スクリプト系 |
| `generic` | 上記以外 |

実装の正はメモリ上の `CodingWorkspaceIndex.kind`（走査結果）。DISK の `meta.json` に書く場合も再オープン時に走査で上書きしてよい。

### 2.3 索引キャッシュ（任意）

| 項目 | 備考 |
|------|------|
| generatedAt | |
| files[] | relativePath／size／mtime／ext |
| truncated | 上限超過フラグ |

キャッシュ破損・古い場合は再走査。削除しても機能は落ちない。

---

## 3. index.json（案）

```json
{
  "version": 1,
  "recentWorkspaces": [
    {
      "rootPath": "/Users/…/my_app",
      "displayName": "my_app",
      "lastOpenedAt": "2026-10-10T12:00:00.000Z"
    }
  ],
  "folderTreeExpanded": {
    "/Users/…/my_app": {
      "lib": true,
      "lib/features": true,
      "document": false
    }
  }
}
```

会話の `threads` は書かない。

---

## 4. thread JSON

書かない。

---

## 5. 削除

| 操作 | 挙動 |
|------|------|
| スレッド削除 | 会話は保存しない。削除操作はない |
| ワークスペース履歴削除 | recent から除去。索引キャッシュ削除可。ディスク上のソースは触らない |
| 全クリア | 確認必須。`coding_assist/` 配下を空に近づけてよい |

ソースファイルの削除は Agent ツール経由かつ確認必須（MVP では `propose_patch` の更新のみでも可）。

---

## 6. 端末設定との境界

モデル／ctx／thinking のコーディング用キーは [DATA_端末設定.md](./DATA_端末設定.md)（S11）。  
コーディング用 ctx の既定は **131072（128k）**。UI 選択肢の上限は S11 どおり **262144（256k）**。  
直近ワークスペースパス一覧は `coding_assist/index.json` の `recentWorkspaces` を正とし、必要なら SharedPreferences に「最後に開いた id」だけ持ってよい。  
フォルダ操作の展開／折りたたみは同じ `index.json` の `folderTreeExpanded`（ワークスペース絶対パス → 相対ディレクトリ → 展開しているか）。未記録のパスは S16 の既定展開。直近に書いたワークスペースを最大 32 件残す。最近使った一覧から消しても、この展開記録は残る。

S16 表示用 UI（フォントサイズ・インデント幅・**プロンプト補助お気に入り**）は SharedPreferences（`CodingUiSettingsLocalDataSource`）。お気に入りは `coding_ui_prompt_favorites`（文字列 ID のリスト・最大2。S16 §2.3.0）。

---

## 7. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-29 | 会話 JSON は書かない。`index.json` は直近ワークスペースとフォルダ展開のみ |
| 2026-10-22 | メッセージの無い「新規」は保存しない。一覧取得時に空の「新規」を削除する（S16 §2.3） |
| 2026-10-16 | プロンプト補助お気に入り（`coding_ui_prompt_favorites`・最大2）を §6 に追記（S16 §2.3.0） |
| 2026-10-14 | コーディング用 ctx 既定 128k・上限 256k を §6 に明記（S11／DATA_端末設定追随） |
| 2026-10-14 | workspaceKind に `android` を追加（S16 第四ターゲット。python は第五） |
| 2026-10-14 | **一括反映**: workspaceKind 全値（flutter／swiftXcode／react／python／generic）と判定の正本参照（S16 §4.1a）。ビュー状態は非永続と明記 |
| 2026-10-14 | workspaceKind に `react` を追加（S16 第三ターゲット。python は第四） |
| 2026-10-14 | workspaceKind に `python` を追加（S16 第三ターゲット） |
| 2026-10-14 | workspaceKind（flutter／swiftXcode／generic）を meta 任意項目として追記（S16 第二ターゲット） |
| 2026-10-14 | 送信前取り込み／選択範囲は非永続と明記。pending の Update／Add 役割を S16 追随 |
| 2026-10-13 | pendingPatches の `isAddFile` をファイル作成案（人手承認）として明記（S16 §5.3.2） |
| 2026-10-13 | コンテキスト圧縮用: `compactedSummary`／`compactedAt`、`contextWarningLevel` に `compacted`。messages は UI 正・API は都度再構築（S16 §5.7） |
| 2026-10-10 | 初版ドラフト。`coding_assist/`・index／thread／workspace 索引 |
| 2026-10-11 | MVP 実装済に更新（S16 追随） |
| 2026-10-12 | Git は WS 側 `.git` 対象である旨を明記（S16 実用追随） |
| 2026-10-12 | ワークスペース＝開いたフォルダである旨を明記。状態を MVP＋実用（一部）に更新 |
