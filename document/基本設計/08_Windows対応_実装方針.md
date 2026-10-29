# Windows 対応：実装方針

最終更新: 2026-10-29  
位置づけ: macOS 初期実装が一巡したあとの **Windows 移植方針**。S16 入口は有効化済み。受け入れ確認は Windows 機で続行。  
関連: [04_非機能制約OS差分.md](./04_非機能制約OS差分.md)、[05_運用配布保守.md](./05_運用配布保守.md)、`document/配布方法/windows/`

---

## 1. ゴール

| 項目 | 方針 |
|------|------|
| 対象 | Flutter デスクトップの **Windows 10/11（64bit）** |
| UI | **S16 を有効化**（現状の入口閉鎖を解除） |
| LLM | 同梱／配置した **`llama-server.exe`** ＋ユーザー追加 GGUF（mac と同じ契約） |
| 配布 | 当面 **zip 一式**（`lmcode.exe` + `data` + DLL + `local_llm\`）。MSIX は後追い可 |
| クロスビルド | **不可**。ビルド・動作確認は Windows 実機（または Windows CI） |

---

## 2. 現状（調査時点）

| 項目 | 状態 |
|------|------|
| `windows/` ランナー | あり（`BINARY_NAME=lmcode`） |
| `.vscode/launch.json` | `deviceId: windows` 構成あり |
| S16 入口 | `CodingAssistAvailability` で **Web 以外は有効**（Windows 含む） |
| LLM 起動／停止 | `llama-server.exe`・`taskkill`・`USERPROFILE` 分岐あり |
| ターミナル | `COMSPEC`／`powershell.exe`、`flutter_pty` は Windows 対応 |
| Dart／Flutter 解決 | `.bat` / `.exe` / `where` 分岐あり |
| RAM 表示 | **必須**。macOS／Windows とも `CodingSystemMemory` 実装済み（Windows 機で表示確認） |
| 配布ドキュメント | zip 想定の下書きのみ |

---

## 3. 開発機セットアップ（Windows）

1. Git for Windows  
2. Flutter SDK（Windows desktop 有効）  
3. **Visual Studio 2022** ＋ワークロード「**C++ によるデスクトップ開発**」  
   - VS 2026 のみの環境は Flutter 版に注意（3.38.2 以降で対応が進んだ）。当面は 2022 推奨  
4. 確認:

```powershell
flutter doctor -v
flutter devices
flutter pub get
flutter run -d windows
flutter build windows --release
```

成果物目安: `build\windows\x64\runner\Release\`（`lmcode.exe` / `*.dll` / `data\`）

---

## 4. 実装タスク（Windows 機で続行）

### 4.1 入口・設計追随（必須）

| # | 作業 | メモ |
|---|------|------|
| W1 | `CodingAssistAvailability.isUiEnabled` を Windows でも true | **完了**（2026-10-29）。GPU 必須条件にはしない |
| W2 | 本ファイル・`04`・配布 README の「入口非提供」を更新 | **完了** |
| W3 | S16 起動〜フォルダオープン〜編集のスモーク | Windows 機で確認 |

### 4.2 サイドカー・ランタイム（必須）

| # | 作業 | メモ |
|---|------|------|
| W4 | `llama-server.exe` の入手／配置規約確定 | 探索順は既存: `%USERPROFILE%\Documents\LMCode\local_llm\` および exe 隣 `local_llm\` |
| W5 | Release zip に `local_llm\llama-server.exe` を含める手順 | **GGUF は同梱しない** |
| W6 | VC++ 再頒布 DLL の要否確認 | 不足時は exe 隣に同梱 |

### 4.3 S16 機能差分（必須／任意）

| 機能 | Windows | 方針 |
|------|---------|------|
| エディタ・Agent・パッチ | ○ | mac と同等を目指す |
| 内蔵ターミナル | ○ | `flutter_pty`。実機で確認 |
| Dart Analysis Server | ○ | Flutter／Dart パス（S11） |
| **RAM 使用率／上位プロセス** | **○ 必須** | `CodingSystemMemory`（PowerShell）。欠落させない |
| Swift / SourceKit-LSP | × | macOS のみ。UI は出さない／無効のまま |
| スリープ抑制等 | 任意 | mac 専用は no-op のままで可。必要なら後続 |

### 4.4 メモリ取得（必須・詳細）

S16 ツールバーの RAM 表示（`CodingRamUsageIndicator`）は過大モデル選定の目安のため、**Windows でも必須**。

| 項目 | 方針 |
|------|------|
| API | 外部プロセス。追加ネイティブプラグインは避ける |
| 使用率 | PowerShell `Win32_OperatingSystem` の Total／Free（KB）から算出 |
| 上位プロセス | `Get-Process` の `WorkingSet64` 降順。表示名は `ProcessName` |
| 失敗時 | 既存どおり `usagePercent: null`・空リスト（UI は壊れない） |
| 実装箇所 | `lib/features/coding_assist/data/coding_system_memory.dart`（**コード反映済み**。実機確認は Windows 機） |

---

## 5. 配布形（当面）

```text
LMCode-Windows.zip
  lmcode.exe
  *.dll
  data\
  local_llm\
    llama-server.exe
    models\          … 空でも可（ユーザーが S11a で追加）
```

* SmartScreen は社内アルファ想定で「実行」誘導。署名は社内ポリシーに従う。  
* Store／自動更新は初期必須としない。

---

## 6. やらないこと（初期）

* macOS からの Windows クロスコンパイル  
* Swift 補完の Windows 移植  
* 会議・ASR・カレンダー等（本リポジトリ対象外）  
* GGUF のライセンス保証・同梱  

---

## 7. 受け入れ（Windows 機）

- [ ] `flutter doctor` で Windows toolchain OK  
- [ ] `flutter run -d windows` で S16 起動  
- [ ] RAM ％が表示され、クリックで上位プロセスが出る  
- [ ] S11a で GGUF 追加 → Agent 応答  
- [ ] ターミナルでシェルが動く  
- [ ] Release フォルダを zip 展開しても起動する  

---

## 8. 版履歴

| 日付 | 内容 |
|------|------|
| 2026-10-29 | W1／W2 完了。S16 入口有効化・設計追随 |
| 2026-10-28 | 初版。S16 有効化方針・ビルド要件・RAM 必須を固定 |
