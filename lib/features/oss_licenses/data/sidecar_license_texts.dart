/// アプリ周辺コンポーネントの OSS ライセンス本文。
/// ローカル LLM の GGUF はユーザー追加のため、モデル本体のライセンスは掲載しない。
/// [registerSidecarLicenses] から [LicenseRegistry] に登録する。
library;

/// 1 件分の登録エントリ。
class SidecarLicenseEntry {
  const SidecarLicenseEntry({
    required this.packageName,
    required this.licenseText,
  });

  /// [LicensePage] 一覧に出る名前。
  final String packageName;

  /// ライセンス本文。
  final String licenseText;
}

/// 登録対象一覧（サイドカー等）。
/// LLM GGUF は同梱しないため、ここには載せない（取り込み時の自己責任注記を正とする）。
/// ASR／仮想マイク等の旧アプリ依存は本リポジトリ対象外のため掲載しない。
const List<SidecarLicenseEntry> kSidecarLicenseEntries = [
  // ローカル LLM サイドカー（llama-server）
  // 出典: https://github.com/ggml-org/llama.cpp/blob/master/LICENSE （2026-10-28 確認）
  SidecarLicenseEntry(
    packageName: 'llama.cpp',
    licenseText: '''MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---
llama.cpp はアプリが起動するローカル LLM サーバー（llama-server）の上流です。
GGUF モデル本体のライセンスは本一覧に含めません（ユーザー追加・利用者責任）。
''',
  ),
];
