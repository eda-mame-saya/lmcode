import 'package:flutter/material.dart';

import '../../theme.dart';

/// ユーザーがカスタムできる色トークン（設定 UI・永続化キー）。
enum AppColorToken {
  primary(id: 'primary', label: 'プライマリ', group: 'ブランド'),
  onPrimary(id: 'onPrimary', label: 'プライマリ上の文字', group: 'ブランド'),
  secondary(id: 'secondary', label: 'セカンダリ', group: 'ブランド'),
  pageBackground(id: 'pageBackground', label: 'ページ背景', group: 'ブランド'),
  dialogBarrier(
    id: 'dialogBarrier',
    label: 'ダイアログ遮光',
    group: 'ダイアログ',
    enableAlpha: true,
  ),
  dialogSurface(id: 'dialogSurface', label: 'ダイアログ地', group: 'ダイアログ'),
  dialogCancel(id: 'dialogCancel', label: 'キャンセルボタン', group: 'ダイアログ'),
  destructive(id: 'destructive', label: '破壊的操作', group: 'ダイアログ'),
  editorBackground(id: 'editorBackground', label: 'エディタ背景', group: 'エディタ'),
  editorGutterBackground(
    id: 'editorGutterBackground',
    label: '行番号ガター',
    group: 'エディタ',
  ),
  editorTabBarBackground(
    id: 'editorTabBarBackground',
    label: 'タブバー',
    group: 'エディタ',
  ),
  minimapBackground(id: 'minimapBackground', label: 'ミニマップ', group: 'エディタ'),
  terminalBackground(
    id: 'terminalBackground',
    label: 'ターミナル背景',
    group: 'エディタ',
  ),
  previewBackground(
    id: 'previewBackground',
    label: 'プレビュー背景',
    group: '本文',
  ),
  previewForeground(
    id: 'previewForeground',
    label: 'プレビュー文字',
    group: '本文',
  ),
  codeBlockBackground(
    id: 'codeBlockBackground',
    label: 'コードブロック',
    group: '本文',
  ),
  subtleBorder(id: 'subtleBorder', label: '細い枠線', group: '本文'),
  blockquoteBorder(
    id: 'blockquoteBorder',
    label: '引用バー',
    group: '本文',
  ),
  ruleBorder(id: 'ruleBorder', label: '区切り線', group: '本文'),
  chatUserBubble(id: 'chatUserBubble', label: 'ユーザー吹き出し', group: '本文'),
  contentForeground(id: 'contentForeground', label: '本文', group: '本文'),
  contentMuted(id: 'contentMuted', label: '補助文字', group: '本文'),
  contentFaint(id: 'contentFaint', label: '薄いアイコン', group: '本文'),
  diffAddBackground(
    id: 'diffAddBackground',
    label: '追加行の地',
    group: '差分',
  ),
  diffAddForeground(
    id: 'diffAddForeground',
    label: '追加行の文字',
    group: '差分',
  ),
  diffRemoveBackground(
    id: 'diffRemoveBackground',
    label: '削除行の地',
    group: '差分',
  ),
  diffRemoveForeground(
    id: 'diffRemoveForeground',
    label: '削除行の文字',
    group: '差分',
  ),
  statusRunning(id: 'statusRunning', label: '起動中インジケータ', group: 'ステータス'),
  panelAccentSoft(
    id: 'panelAccentSoft',
    label: '薄いアクセント地',
    group: 'ステータス',
    enableAlpha: true,
  );

  const AppColorToken({
    required this.id,
    required this.label,
    required this.group,
    this.enableAlpha = false,
  });

  final String id;
  final String label;
  final String group;
  final bool enableAlpha;

  static AppColorToken? byId(String id) {
    for (final token in values) {
      if (token.id == id) return token;
    }
    return null;
  }

  /// 設定 UI のグループ見出し順。
  static const groupOrder = <String>[
    'ブランド',
    'ダイアログ',
    'エディタ',
    '本文',
    '差分',
    'ステータス',
  ];

  Color read(AppColors colors) => switch (this) {
        primary => colors.primary,
        onPrimary => colors.onPrimary,
        secondary => colors.secondary,
        pageBackground => colors.pageBackground,
        dialogBarrier => colors.dialogBarrier,
        dialogSurface => colors.dialogSurface,
        dialogCancel => colors.dialogCancel,
        destructive => colors.destructive,
        editorBackground => colors.editorBackground,
        editorGutterBackground => colors.editorGutterBackground,
        editorTabBarBackground => colors.editorTabBarBackground,
        minimapBackground => colors.minimapBackground,
        terminalBackground => colors.terminalBackground,
        previewBackground => colors.previewBackground,
        previewForeground => colors.previewForeground,
        codeBlockBackground => colors.codeBlockBackground,
        subtleBorder => colors.subtleBorder,
        blockquoteBorder => colors.blockquoteBorder,
        ruleBorder => colors.ruleBorder,
        chatUserBubble => colors.chatUserBubble,
        contentForeground => colors.contentForeground,
        contentMuted => colors.contentMuted,
        contentFaint => colors.contentFaint,
        diffAddBackground => colors.diffAddBackground,
        diffAddForeground => colors.diffAddForeground,
        diffRemoveBackground => colors.diffRemoveBackground,
        diffRemoveForeground => colors.diffRemoveForeground,
        statusRunning => colors.statusRunning,
        panelAccentSoft => colors.panelAccentSoft,
      };

  AppColors write(AppColors colors, Color value) => switch (this) {
        primary => colors.copyWith(primary: value),
        onPrimary => colors.copyWith(onPrimary: value),
        secondary => colors.copyWith(secondary: value),
        pageBackground => colors.copyWith(pageBackground: value),
        dialogBarrier => colors.copyWith(dialogBarrier: value),
        dialogSurface => colors.copyWith(dialogSurface: value),
        dialogCancel => colors.copyWith(dialogCancel: value),
        destructive => colors.copyWith(destructive: value),
        editorBackground => colors.copyWith(editorBackground: value),
        editorGutterBackground =>
          colors.copyWith(editorGutterBackground: value),
        editorTabBarBackground =>
          colors.copyWith(editorTabBarBackground: value),
        minimapBackground => colors.copyWith(minimapBackground: value),
        terminalBackground => colors.copyWith(terminalBackground: value),
        previewBackground => colors.copyWith(previewBackground: value),
        previewForeground => colors.copyWith(previewForeground: value),
        codeBlockBackground => colors.copyWith(codeBlockBackground: value),
        subtleBorder => colors.copyWith(subtleBorder: value),
        blockquoteBorder => colors.copyWith(blockquoteBorder: value),
        ruleBorder => colors.copyWith(ruleBorder: value),
        chatUserBubble => colors.copyWith(chatUserBubble: value),
        contentForeground => colors.copyWith(contentForeground: value),
        contentMuted => colors.copyWith(contentMuted: value),
        contentFaint => colors.copyWith(contentFaint: value),
        diffAddBackground => colors.copyWith(diffAddBackground: value),
        diffAddForeground => colors.copyWith(diffAddForeground: value),
        diffRemoveBackground => colors.copyWith(diffRemoveBackground: value),
        diffRemoveForeground => colors.copyWith(diffRemoveForeground: value),
        statusRunning => colors.copyWith(statusRunning: value),
        panelAccentSoft => colors.copyWith(panelAccentSoft: value),
      };
}

extension AppColorsOverrides on AppColors {
  /// SharedPreferences に保存した ARGB マップを適用する。
  AppColors applyOverrides(Map<String, int> overrides) {
    if (overrides.isEmpty) return this;
    var next = this;
    for (final entry in overrides.entries) {
      final token = AppColorToken.byId(entry.key);
      if (token == null) continue;
      next = token.write(next, Color(entry.value));
    }
    return next;
  }
}
