import 'package:flutter/material.dart';

/// ブランド既定値（濃いオレンジ プライマリ）。テーマ生成の seed／フォールバック用。
/// 画面・ウィジェットでは [AppColors.of] を使うこと。
abstract final class AppBrandColors {
  static const primary = Color(0xFFE65100);
  static const secondary = Color(0xFFFFF3E0);
  static const pageBackground = Color(0xFFFFFAF7);
}

/// 画面・パーツ向けセマンティック色。
///
/// Material [ColorScheme] に載らないアプリ固有色（エディタ／差分／ダイアログ等）を
/// light／dark で対にする。ユーザーカスタムは [AppThemeController] 経由で
/// [copyWith]／オーバーライドを載せる。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.pageBackground,
    required this.dialogBarrier,
    required this.dialogSurface,
    required this.dialogCancel,
    required this.destructive,
    required this.editorBackground,
    required this.editorGutterBackground,
    required this.editorTabBarBackground,
    required this.minimapBackground,
    required this.terminalBackground,
    required this.previewBackground,
    required this.previewForeground,
    required this.codeBlockBackground,
    required this.subtleBorder,
    required this.blockquoteBorder,
    required this.ruleBorder,
    required this.chatUserBubble,
    required this.contentForeground,
    required this.contentMuted,
    required this.contentFaint,
    required this.diffAddBackground,
    required this.diffAddForeground,
    required this.diffRemoveBackground,
    required this.diffRemoveForeground,
    required this.statusRunning,
    required this.panelAccentSoft,
  });

  /// ブランド／アクセント。
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color pageBackground;

  /// 確認ダイアログ（UI共通_モーダル基本系）。
  final Color dialogBarrier;
  final Color dialogSurface;
  final Color dialogCancel;
  final Color destructive;

  /// コードエディタ／ミニマップ／ターミナル。
  final Color editorBackground;
  final Color editorGutterBackground;
  final Color editorTabBarBackground;
  final Color minimapBackground;
  final Color terminalBackground;

  /// Markdown／マークアップ プレビュー・チャット本文。
  final Color previewBackground;
  final Color previewForeground;
  final Color codeBlockBackground;
  final Color subtleBorder;
  final Color blockquoteBorder;
  final Color ruleBorder;
  final Color chatUserBubble;
  final Color contentForeground;
  final Color contentMuted;
  final Color contentFaint;

  /// パッチ差分。
  final Color diffAddBackground;
  final Color diffAddForeground;
  final Color diffRemoveBackground;
  final Color diffRemoveForeground;

  /// ステータス（サイドカー起動中など）。
  final Color statusRunning;

  /// 取り込みバー等の薄いブランド地。
  final Color panelAccentSoft;

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  /// ライト既定（現行アプリ見た目を踏襲）。
  static const light = AppColors(
    primary: AppBrandColors.primary,
    onPrimary: Color(0xFFFFFFFF),
    secondary: AppBrandColors.secondary,
    pageBackground: AppBrandColors.pageBackground,
    dialogBarrier: Color(0x8C000000),
    dialogSurface: Color(0xFFFFFFFF),
    dialogCancel: Color(0xFF9E9E9E),
    destructive: Color(0xFFE53935),
    editorBackground: Color(0xFFFAFAFA),
    editorGutterBackground: Color(0xFFEEEEEE),
    editorTabBarBackground: Color(0xFFF0F0F0),
    minimapBackground: Color(0xFFF0F0F0),
    terminalBackground: Color(0xFF1E1E1E),
    previewBackground: Color(0xFFFFFFFF),
    previewForeground: Color(0xDE000000),
    codeBlockBackground: Color(0xFFEEEEEE),
    subtleBorder: Color(0xFFE0E0E0),
    blockquoteBorder: Color(0xFFBDBDBD),
    ruleBorder: Color(0xFFE0E0E0),
    chatUserBubble: Color(0xFFFFFFFF),
    contentForeground: Color(0xDE000000),
    contentMuted: Color(0x8A000000),
    contentFaint: Color(0x73000000),
    diffAddBackground: Color(0xFFE8F5E9),
    diffAddForeground: Color(0xFF1B5E20),
    diffRemoveBackground: Color(0xFFFFEBEE),
    diffRemoveForeground: Color(0xFFB71C1C),
    statusRunning: Color(0xFF2E7D32),
    panelAccentSoft: Color(0x8CFFF3E0),
  );

  /// ダーク既定（Atom One Dark 系エディタ色に合わせる）。
  static const dark = AppColors(
    primary: AppBrandColors.primary,
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF3A2210),
    pageBackground: Color(0xFF121212),
    dialogBarrier: Color(0x8C000000),
    dialogSurface: Color(0xFF1E1E1E),
    dialogCancel: Color(0xFF757575),
    destructive: Color(0xFFEF5350),
    editorBackground: Color(0xFF282C34),
    editorGutterBackground: Color(0xFF21252B),
    editorTabBarBackground: Color(0xFF21252B),
    minimapBackground: Color(0xFF21252B),
    terminalBackground: Color(0xFF1E1E1E),
    previewBackground: Color(0xFF1E1E1E),
    previewForeground: Color(0xEBFFFFFF),
    codeBlockBackground: Color(0xFF2D2D2D),
    subtleBorder: Color(0xFF3A3A3A),
    blockquoteBorder: Color(0xFF757575),
    ruleBorder: Color(0xFF616161),
    chatUserBubble: Color(0xFF2A2A2A),
    contentForeground: Color(0xDEFFFFFF),
    contentMuted: Color(0x99FFFFFF),
    contentFaint: Color(0x73FFFFFF),
    diffAddBackground: Color(0xFF1B3A1E),
    diffAddForeground: Color(0xFFA5D6A7),
    diffRemoveBackground: Color(0xFF3A1B1B),
    diffRemoveForeground: Color(0xFFEF9A9A),
    statusRunning: Color(0xFF66BB6A),
    panelAccentSoft: Color(0x663A2210),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? pageBackground,
    Color? dialogBarrier,
    Color? dialogSurface,
    Color? dialogCancel,
    Color? destructive,
    Color? editorBackground,
    Color? editorGutterBackground,
    Color? editorTabBarBackground,
    Color? minimapBackground,
    Color? terminalBackground,
    Color? previewBackground,
    Color? previewForeground,
    Color? codeBlockBackground,
    Color? subtleBorder,
    Color? blockquoteBorder,
    Color? ruleBorder,
    Color? chatUserBubble,
    Color? contentForeground,
    Color? contentMuted,
    Color? contentFaint,
    Color? diffAddBackground,
    Color? diffAddForeground,
    Color? diffRemoveBackground,
    Color? diffRemoveForeground,
    Color? statusRunning,
    Color? panelAccentSoft,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      pageBackground: pageBackground ?? this.pageBackground,
      dialogBarrier: dialogBarrier ?? this.dialogBarrier,
      dialogSurface: dialogSurface ?? this.dialogSurface,
      dialogCancel: dialogCancel ?? this.dialogCancel,
      destructive: destructive ?? this.destructive,
      editorBackground: editorBackground ?? this.editorBackground,
      editorGutterBackground:
          editorGutterBackground ?? this.editorGutterBackground,
      editorTabBarBackground:
          editorTabBarBackground ?? this.editorTabBarBackground,
      minimapBackground: minimapBackground ?? this.minimapBackground,
      terminalBackground: terminalBackground ?? this.terminalBackground,
      previewBackground: previewBackground ?? this.previewBackground,
      previewForeground: previewForeground ?? this.previewForeground,
      codeBlockBackground: codeBlockBackground ?? this.codeBlockBackground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      blockquoteBorder: blockquoteBorder ?? this.blockquoteBorder,
      ruleBorder: ruleBorder ?? this.ruleBorder,
      chatUserBubble: chatUserBubble ?? this.chatUserBubble,
      contentForeground: contentForeground ?? this.contentForeground,
      contentMuted: contentMuted ?? this.contentMuted,
      contentFaint: contentFaint ?? this.contentFaint,
      diffAddBackground: diffAddBackground ?? this.diffAddBackground,
      diffAddForeground: diffAddForeground ?? this.diffAddForeground,
      diffRemoveBackground: diffRemoveBackground ?? this.diffRemoveBackground,
      diffRemoveForeground: diffRemoveForeground ?? this.diffRemoveForeground,
      statusRunning: statusRunning ?? this.statusRunning,
      panelAccentSoft: panelAccentSoft ?? this.panelAccentSoft,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColors(
      primary: lerpColor(primary, other.primary),
      onPrimary: lerpColor(onPrimary, other.onPrimary),
      secondary: lerpColor(secondary, other.secondary),
      pageBackground: lerpColor(pageBackground, other.pageBackground),
      dialogBarrier: lerpColor(dialogBarrier, other.dialogBarrier),
      dialogSurface: lerpColor(dialogSurface, other.dialogSurface),
      dialogCancel: lerpColor(dialogCancel, other.dialogCancel),
      destructive: lerpColor(destructive, other.destructive),
      editorBackground: lerpColor(editorBackground, other.editorBackground),
      editorGutterBackground:
          lerpColor(editorGutterBackground, other.editorGutterBackground),
      editorTabBarBackground:
          lerpColor(editorTabBarBackground, other.editorTabBarBackground),
      minimapBackground: lerpColor(minimapBackground, other.minimapBackground),
      terminalBackground:
          lerpColor(terminalBackground, other.terminalBackground),
      previewBackground: lerpColor(previewBackground, other.previewBackground),
      previewForeground: lerpColor(previewForeground, other.previewForeground),
      codeBlockBackground:
          lerpColor(codeBlockBackground, other.codeBlockBackground),
      subtleBorder: lerpColor(subtleBorder, other.subtleBorder),
      blockquoteBorder: lerpColor(blockquoteBorder, other.blockquoteBorder),
      ruleBorder: lerpColor(ruleBorder, other.ruleBorder),
      chatUserBubble: lerpColor(chatUserBubble, other.chatUserBubble),
      contentForeground: lerpColor(contentForeground, other.contentForeground),
      contentMuted: lerpColor(contentMuted, other.contentMuted),
      contentFaint: lerpColor(contentFaint, other.contentFaint),
      diffAddBackground: lerpColor(diffAddBackground, other.diffAddBackground),
      diffAddForeground: lerpColor(diffAddForeground, other.diffAddForeground),
      diffRemoveBackground:
          lerpColor(diffRemoveBackground, other.diffRemoveBackground),
      diffRemoveForeground:
          lerpColor(diffRemoveForeground, other.diffRemoveForeground),
      statusRunning: lerpColor(statusRunning, other.statusRunning),
      panelAccentSoft: lerpColor(panelAccentSoft, other.panelAccentSoft),
    );
  }
}

/// アプリ全体の [ThemeData] を組み立てる。
///
/// [colors] を渡すと light／dark 既定の上にユーザーカスタムを載せる。
ThemeData buildAppTheme({
  Brightness brightness = Brightness.light,
  AppColors? colors,
}) {
  final appColors =
      colors ?? (brightness == Brightness.dark ? AppColors.dark : AppColors.light);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: appColors.primary,
    brightness: brightness,
    primary: appColors.primary,
    onPrimary: appColors.onPrimary,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: appColors.pageBackground,
    extensions: <ThemeExtension<dynamic>>[appColors],
    appBarTheme: AppBarTheme(
      backgroundColor: appColors.secondary,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: appColors.primary,
        foregroundColor: appColors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

ThemeData buildAppLightTheme({AppColors? colors}) =>
    buildAppTheme(brightness: Brightness.light, colors: colors);

ThemeData buildAppDarkTheme({AppColors? colors}) =>
    buildAppTheme(brightness: Brightness.dark, colors: colors);
