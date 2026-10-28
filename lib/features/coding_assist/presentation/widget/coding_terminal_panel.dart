import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../../../theme.dart';
import '../../domain/coding_terminal_shell.dart';

/// エディタ下部の折りたたみ式ターミナル（PTY + xterm）。
///
/// 初期 cwd は [workingDirectory]（選択中ワークスペース）。
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

  @override
  State<CodingTerminalPanel> createState() => _CodingTerminalPanelState();
}

class _CodingTerminalPanelState extends State<CodingTerminalPanel> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  Pty? _pty;
  String? _startError;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
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
  }

  @override
  void dispose() {
    _killPty();
    _terminalController.dispose();
    super.dispose();
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
                  IconButton(
                    tooltip: widget.collapsed ? 'ターミナルを展開' : 'ターミナルを折りたたむ',
                    onPressed: widget.onToggleCollapsed,
                    icon: Icon(
                      widget.collapsed
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const Text(
                    'ターミナル',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                          controller: _terminalController,
                          theme: TerminalThemes.defaultTheme,
                          textStyle: const TerminalStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          padding: const EdgeInsets.all(6),
                          autofocus: false,
                          hardwareKeyboardOnly: true,
                          backgroundOpacity: 1,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
