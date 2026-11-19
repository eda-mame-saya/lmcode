import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../../../theme.dart';
import '../../domain/coding_terminal_shell.dart';

/// エディタ下部の折りたたみ式ターミナル（PTY + xterm）。
///
/// 初期 cwd は [workingDirectory]（WS 選択時はそのルート、未選択時はホーム）。
/// 折りたたみ時もシェルは維持する。
class CodingTerminalPanel extends StatefulWidget {
  const CodingTerminalPanel({
    super.key,
    required this.workingDirectory,
    required this.collapsed,
    required this.height,
    required this.onToggleCollapsed,
    required this.onHeightDrag,
  });

  final String workingDirectory;
  final bool collapsed;
  final double height;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<double> onHeightDrag;

  static const headerHeight = 32.0;
  static const resizeHandleHeight = 6.0;
  static const heightMin = 120.0;
  static const heightDefault = 200.0;

  /// 最大化時に中央ペインへ残すエディタ側の最小高さ。
  /// 0 ならターミナルをエディタ部上端まで広げられる。
  static const editorFloorWhenMaximized = 0.0;

  @override
  State<CodingTerminalPanel> createState() => _CodingTerminalPanelState();
}

class _CodingTerminalPanelState extends State<CodingTerminalPanel> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  Pty? _pty;
  String? _startError;
  bool _exited = false;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _terminalController.addListener(_onControllerChanged);
    _focusNode = FocusNode(debugLabel: 'codingTerminal');
    _focusNode.addListener(_onFocusChanged);
    _terminal.onOutput = _onTerminalOutput;
    _terminal.onResize = _onTerminalResize;
    _startShell();
  }

  @override
  void didUpdateWidget(covariant CodingTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workingDirectory != widget.workingDirectory) {
      _restartShell();
    }
    if (oldWidget.collapsed && !widget.collapsed) {
      // 展開直後に IME 用 TextInput を開き直す。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureInputConnection();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _terminalController.removeListener(_onControllerChanged);
    _killPty();
    _terminalController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final next = _terminalController.selection != null;
    if (next == _hasSelection) return;
    setState(() => _hasSelection = next);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _ensureInputConnection();
    }
  }

  /// xterm の CustomTextEdit は focus 時に `consumeKeyboardToken` が無いと
  /// TextInput を開かないことがある。明示的に [TerminalViewState.requestKeyboard]
  /// を呼び、日本語 IME 用の接続を確保する。
  void _ensureInputConnection() {
    _terminalViewKey.currentState?.requestKeyboard();
  }

  void _onTerminalOutput(String data) {
    final pty = _pty;
    if (pty == null) return;
    pty.write(Uint8List.fromList(utf8.encode(data)));
  }

  void _onTerminalResize(int width, int height, int pixelWidth, int pixelHeight) {
    final pty = _pty;
    if (pty == null) return;
    if (width <= 0 || height <= 0) return;
    pty.resize(height, width);
  }

  void _killPty() {
    final pty = _pty;
    _pty = null;
    if (pty == null) return;
    try {
      pty.kill();
    } catch (_) {}
  }

  void _restartShell() {
    _killPty();
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);
    setState(() {
      _startError = null;
      _exited = false;
      _hasSelection = false;
    });
    _startShell();
  }

  void _startShell() {
    final cwd = widget.workingDirectory;
    if (cwd.trim().isEmpty) {
      setState(() => _startError = '作業ディレクトリが未設定です');
      return;
    }
    try {
      final executable = CodingTerminalShell.executable();
      final arguments = CodingTerminalShell.arguments();
      final pty = Pty.start(
        executable,
        arguments: arguments,
        workingDirectory: cwd,
        environment: Platform.environment,
        rows: _terminal.viewHeight > 0 ? _terminal.viewHeight : 24,
        columns: _terminal.viewWidth > 0 ? _terminal.viewWidth : 80,
      );
      _pty = pty;
      pty.output.listen(
        (data) {
          if (!mounted) return;
          _terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onError: (Object e) {
          if (!mounted) return;
          _terminal.write('\r\n[ターミナル出力エラー] $e\r\n');
        },
      );
      pty.exitCode.then((code) {
        if (!mounted) return;
        setState(() => _exited = true);
        _terminal.write('\r\n[シェル終了: $code] 再起動ボタンで再開できます。\r\n');
      });
      // ログインシェルのプロファイルが cwd を変える場合があるため明示移動。
      final escaped = cwd.replaceAll("'", "'\\''");
      pty.write(Uint8List.fromList(utf8.encode("cd '$escaped'\n")));
    } catch (e) {
      setState(() => _startError = 'ターミナルを起動できませんでした: $e');
    }
  }

  String? _selectedText() {
    final selection = _terminalController.selection;
    if (selection == null) return null;
    final text = _terminal.buffer.getText(selection);
    if (text.isEmpty) return null;
    return text;
  }

  Future<bool> _copySelection() async {
    final text = _selectedText();
    if (text == null) return false;
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _terminal.paste(text);
    _terminalController.clearSelection();
    _ensureInputConnection();
  }

  Future<void> _onSecondaryTap(
    TapDownDetails details,
    CellOffset _,
  ) async {
    final selection = _selectedText();
    if (selection != null) {
      final copied = await _copySelection();
      if (copied && mounted) {
        _terminalController.clearSelection();
      }
      return;
    }
    await _pasteClipboard();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isControl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    if (isAlt) return KeyEventResult.ignored;

    final key = event.logicalKey;

    final hasSelection = _selectedText() != null;

    // コピー: macOS ⌘C／他 Ctrl+Shift+C。
    // 選択中の Ctrl+C もコピー（無選択なら後続でシェル割り込みへ）。
    final copyChord = key == LogicalKeyboardKey.keyC &&
        !isAlt &&
        ((isMeta && !isControl && !isShift) ||
            (isControl && isShift && !isMeta) ||
            (isControl && !isShift && !isMeta && hasSelection));
    if (copyChord && hasSelection) {
      _copySelection();
      return KeyEventResult.handled;
    }

    // ペースト: macOS ⌘V／他 Ctrl+V・Ctrl+Shift+V。
    final pasteChord = key == LogicalKeyboardKey.keyV &&
        !isAlt &&
        ((isMeta && !isControl && !isShift) || (isControl && !isMeta));
    if (pasteChord) {
      _pasteClipboard();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalHeight = widget.collapsed
        ? CodingTerminalPanel.headerHeight
        : widget.height;

    return SizedBox(
      height: totalHeight,
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.collapsed)
              MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    widget.onHeightDrag(-details.delta.dy);
                  },
                  child: SizedBox(
                    height: CodingTerminalPanel.resizeHandleHeight,
                    child: Center(
                      child: Container(
                        height: 1,
                        color: scheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: CodingTerminalPanel.headerHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: widget.collapsed
                          ? 'ターミナルを展開'
                          : 'ターミナルを折りたたむ',
                      child: InkWell(
                        onTap: widget.onToggleCollapsed,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                widget.collapsed
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 18,
                              ),
                            ),
                            const Text(
                              'ターミナル',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.workingDirectory,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_hasSelection)
                    IconButton(
                      tooltip: '選択範囲をコピー',
                      onPressed: () async {
                        await _copySelection();
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  if (_exited || _startError != null)
                    TextButton(
                      onPressed: _restartShell,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('再起動'),
                    )
                  else
                    IconButton(
                      tooltip: 'シェルを再起動',
                      onPressed: _restartShell,
                      icon: const Icon(Icons.refresh, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.collapsed)
              Expanded(
                child: ColoredBox(
                  color: AppColors.of(context).terminalBackground,
                  child: _startError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _startError!,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      : TerminalView(
                          _terminal,
                          key: _terminalViewKey,
                          controller: _terminalController,
                          focusNode: _focusNode,
                          theme: TerminalThemes.defaultTheme,
                          textStyle: const TerminalStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          padding: const EdgeInsets.all(6),
                          autofocus: false,
                          // false: TextInputClient 経由で IME（日本語など）を受け付ける。
                          // true だとハードキーのみになり変換入力が効かない。
                          hardwareKeyboardOnly: false,
                          keyboardType: TextInputType.text,
                          backgroundOpacity: 1,
                          onKeyEvent: _onKeyEvent,
                          onSecondaryTapDown: _onSecondaryTap,
                          onTapUp: (_, __) {
                            _ensureInputConnection();
                          },
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
