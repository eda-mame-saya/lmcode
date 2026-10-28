import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:re_editor/re_editor.dart';

/// ミニマップのビューポート帯（top / height）。計算不能時は null。
///
/// 短い／空ファイルでは帯の最小高が内容高を超えないよう clamp する
///（`lower > upper` で [num.clamp] が throw するのを防ぐ）。
({double top, double height})? codingMinimapViewportBand({
  required double view,
  required double pixels,
  required double max,
  required int lineCount,
  double linePitch = 2.0,
}) {
  if (view <= 0 || lineCount <= 0) return null;

  final contentH = lineCount * linePitch;
  final total = max + view;

  // 全体がエディタに収まる／スクロール不能
  if (max <= 0.5 || total <= 0) {
    return (top: 0, height: contentH);
  }

  final visibleFrac = (view / total).clamp(0.0, 1.0);
  final minBandH = math.min(linePitch * 4, contentH);
  final bandH = (visibleFrac * contentH).clamp(minBandH, contentH);

  // 最下部: 帯の下端を最終行に密着（空白パディング側に寄せない）
  if (pixels >= max - 1.0) {
    final top = (contentH - bandH).clamp(0.0, contentH);
    return (top: top, height: bandH);
  }

  // 先頭: 帯を上端に
  if (pixels <= 0.5) {
    return (top: 0, height: bandH);
  }

  // 中間: スクロール可能域で帯を線形移動
  final scrollable = (contentH - bandH).clamp(0.0, contentH);
  final top = (pixels / max * scrollable).clamp(0.0, scrollable);
  return (top: top, height: bandH);
}

/// エディタ右端の折りたたみ可能ミニマップ。
///
/// [scrollController] でエディタの垂直スクロール位置を帯表示し、
/// クリック／ドラッグでエディタをその位置へスクロールする。
///
/// 内容高さは「行数 × pitch」のみ（ビューポートまで空白で伸ばさない）。
/// 最下部スクロール時は帯下端を最終行に合わせる。
class CodingMinimap extends StatefulWidget {
  const CodingMinimap({
    super.key,
    required this.editingController,
    required this.scrollController,
    required this.collapsed,
    required this.onToggleCollapsed,
    this.width = 72,
    this.backgroundColor,
    this.foregroundColor,
  });

  final CodeLineEditingController editingController;
  final CodeScrollController scrollController;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final double width;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<CodingMinimap> createState() => _CodingMinimapState();
}

class _CodingMinimapState extends State<CodingMinimap> {
  static const _collapsedWidth = 22.0;
  static const _linePitch = 2.0;

  final _minimapScroll = ScrollController();
  var _repaintScheduled = false;
  var _bandFollowScheduled = false;

  /// レイアウト外で採取したエディタ垂直スクロール寸法。
  double? _editorPixels;
  double? _editorViewport;
  double? _editorMaxExtent;

  ScrollController get _editorVertical =>
      widget.scrollController.verticalScroller;

  @override
  void initState() {
    super.initState();
    widget.editingController.addListener(_scheduleRepaint);
    _editorVertical.addListener(_onEditorScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sampleEditorScroll());
  }

  @override
  void didUpdateWidget(covariant CodingMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editingController != widget.editingController) {
      oldWidget.editingController.removeListener(_scheduleRepaint);
      widget.editingController.addListener(_scheduleRepaint);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.verticalScroller.removeListener(_onEditorScroll);
      _editorVertical.addListener(_onEditorScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) => _sampleEditorScroll());
    }
  }

  @override
  void dispose() {
    widget.editingController.removeListener(_scheduleRepaint);
    _editorVertical.removeListener(_onEditorScroll);
    _minimapScroll.dispose();
    super.dispose();
  }

  void _onEditorScroll() {
    if (_sampleEditorScroll()) {
      _scheduleRepaint();
      _scheduleBandFollow();
    }
  }

  /// true = 値が変わった。
  bool _sampleEditorScroll() {
    final scroller = _editorVertical;
    if (!scroller.hasClients) return false;
    final position = scroller.position;
    if (!position.hasPixels ||
        !position.hasViewportDimension ||
        !position.haveDimensions) {
      return false;
    }
    final pixels = position.pixels;
    final view = position.viewportDimension;
    final max = position.maxScrollExtent;
    if (_editorPixels == pixels &&
        _editorViewport == view &&
        _editorMaxExtent == max) {
      return false;
    }
    _editorPixels = pixels;
    _editorViewport = view;
    _editorMaxExtent = max;
    return true;
  }

  void _scheduleRepaint() {
    if (!mounted || _repaintScheduled) return;
    _repaintScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _repaintScheduled = false;
      if (!mounted) return;
      _sampleEditorScroll();
      setState(() {});
    });
  }

  void _scheduleBandFollow() {
    if (!mounted || _bandFollowScheduled) return;
    _bandFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bandFollowScheduled = false;
      if (mounted) _ensureBandVisible();
    });
  }

  /// エディタのビューポート帯がミニマップ表示外なら追随スクロール。
  void _ensureBandVisible() {
    if (!_minimapScroll.hasClients) return;
    final miniPos = _minimapScroll.position;
    if (!miniPos.hasViewportDimension || !miniPos.haveDimensions) return;
    final viewportH = miniPos.viewportDimension;
    if (viewportH <= 0) return;
    final band = _viewportBand();
    if (band == null) return;
    final mini = _minimapScroll.offset;
    final bandBottom = band.top + band.height;
    if (band.top < mini) {
      _minimapScroll.jumpTo(
        band.top.clamp(0.0, miniPos.maxScrollExtent),
      );
    } else if (bandBottom > mini + viewportH) {
      _minimapScroll.jumpTo(
        (bandBottom - viewportH).clamp(0.0, miniPos.maxScrollExtent),
      );
    }
  }

  List<String> get _lines {
    final text = widget.editingController.text;
    if (text.isEmpty) return const [''];
    return text.split('\n');
  }

  /// 行数ベースの高さのみ（ビューポートまで空白で埋めない）。
  double get _contentHeight =>
      (_lines.length * _linePitch).clamp(_linePitch, 100000.0);

  /// キャッシュ済み寸法＋行数で帯を計算（layout 中でも安全）。
  ({double top, double height})? _viewportBand() {
    final view = _editorViewport;
    final pixels = _editorPixels;
    final max = _editorMaxExtent;
    if (view == null || pixels == null || max == null) return null;
    return codingMinimapViewportBand(
      view: view,
      pixels: pixels,
      max: max,
      lineCount: _lines.length,
      linePitch: _linePitch,
    );
  }

  void _scrollEditorToLocalDy(double localDy, double panelHeight) {
    final lines = _lines;
    if (lines.isEmpty) return;

    final contentH = _contentHeight;
    final miniOffset =
        _minimapScroll.hasClients ? _minimapScroll.offset : 0.0;

    // パネル内クリックを content 座標へ。内容より下の空白は最終行扱い。
    final contentY = (miniOffset + localDy).clamp(0.0, contentH);
    final frac = contentH <= 0 ? 0.0 : (contentY / contentH).clamp(0.0, 1.0);
    final lineIndex =
        (frac * (lines.length - 1)).round().clamp(0, lines.length - 1);

    final scroller = _editorVertical;
    if (scroller.hasClients) {
      final position = scroller.position;
      if (position.hasViewportDimension && position.haveDimensions) {
        final max = position.maxScrollExtent;
        if (max <= 0) {
          // スクロール不要
        } else if (frac >= 1.0 - 1e-6) {
          scroller.jumpTo(max);
        } else if (frac <= 1e-6) {
          scroller.jumpTo(0);
        } else {
          scroller.jumpTo((frac * max).clamp(0.0, max));
        }
        _sampleEditorScroll();
        setState(() {});
      }
    }

    try {
      final pos = CodeLinePosition(index: lineIndex, offset: 0);
      widget.editingController.selection = CodeLineSelection.fromPosition(
        position: pos,
      );
      widget.scrollController.makeVisible(pos);
    } catch (_) {
      // エディタ未接続時は無視
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ?? scheme.surfaceContainerHighest;
    final fg =
        widget.foregroundColor ?? scheme.onSurface.withValues(alpha: 0.45);
    final border = scheme.outlineVariant;
    final viewportColor = scheme.primary.withValues(alpha: 0.22);
    final viewportBorder = scheme.primary.withValues(alpha: 0.55);

    if (widget.collapsed) {
      return SizedBox(
        width: _collapsedWidth,
        child: Material(
          color: bg,
          child: Column(
            children: [
              IconButton(
                tooltip: 'ミニマップを展開',
                onPressed: widget.onToggleCollapsed,
                icon: const Icon(Icons.chevron_left, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 28),
              ),
              Expanded(
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Map',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lines = _lines;
    final contentH = _contentHeight;
    final band = _viewportBand();

    return SizedBox(
      width: widget.width,
      child: Material(
        color: bg,
        child: Column(
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: 'ミニマップを折りたたむ',
                    onPressed: widget.onToggleCollapsed,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: border)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panelH = constraints.maxHeight;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _scrollEditorToLocalDy(d.localPosition.dy, panelH),
                      onVerticalDragUpdate: (d) =>
                          _scrollEditorToLocalDy(d.localPosition.dy, panelH),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          controller: _minimapScroll,
                          child: SizedBox(
                            // 行数分だけ。短いファイルで下に空白帯を作らない。
                            height: contentH,
                            width: widget.width,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size(widget.width, contentH),
                                  painter: _MinimapPainter(
                                    lines: lines,
                                    linePitch: _linePitch,
                                    foreground: fg,
                                  ),
                                ),
                                if (band != null)
                                  Positioned(
                                    top: band.top,
                                    left: 0,
                                    right: 0,
                                    height: band.height,
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: viewportColor,
                                          border: Border.all(
                                            color: viewportBorder,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
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

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.lines,
    required this.linePitch,
    required this.foreground,
  });

  final List<String> lines;
  final double linePitch;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Paint()..color = foreground;
    const left = 4.0;
    final maxW = size.width - 8;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimRight();
      if (trimmed.isEmpty) continue;
      final y = i * linePitch;
      final w = (trimmed.length / 80.0).clamp(0.08, 1.0) * maxW;
      canvas.drawRect(Rect.fromLTWH(left, y, w, 1.2), bar);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.lines != lines || oldDelegate.foreground != foreground;
  }
}
