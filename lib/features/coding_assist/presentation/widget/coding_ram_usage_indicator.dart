import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/coding_system_memory.dart';

/// S16 ツールバー用。RAM 使用率％を定期表示し、タップで上位プロセスを出す。
class CodingRamUsageIndicator extends StatefulWidget {
  const CodingRamUsageIndicator({super.key});

  static const idleInterval = Duration(seconds: 5);
  static const detailInterval = Duration(seconds: 2);

  @override
  State<CodingRamUsageIndicator> createState() =>
  _CodingRamUsageIndicatorState();
}

class _CodingRamUsageIndicatorState extends State<CodingRamUsageIndicator> {
  final _link = LayerLink();
  Timer? _timer;
  OverlayEntry? _overlay;
  int? _percent;
  List<CodingProcessMemory> _top = const [];
  bool _loadingDetail = false;

  bool get _detailOpen => _overlay != null;

  // DateTime? _lastUpdateTime;

  @override
  void initState() {
    super.initState();
    _refresh(includeTop: false);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    final interval = _detailOpen
    ? CodingRamUsageIndicator.detailInterval
    : CodingRamUsageIndicator.idleInterval;
    _timer = Timer.periodic(interval, (_) {
        _refresh(includeTop: _detailOpen);
    });
  }

  Future<void> _refresh({required bool includeTop}) async {
    final snap = await CodingSystemMemory.sample(
      includeTopProcesses: includeTop,
    );
    if (!mounted) return;
    // _lastUpdateTime = DateTime.now();
    setState(() {
        _percent = snap.usagePercent;
        if (includeTop) {
          _top = snap.topProcesses;
          _loadingDetail = false;
        }
    });
    _overlay?.markNeedsBuild();
  }

  void _toggleDetail() {
    if (_detailOpen) {
      _closeDetail();
      return;
    }
    _openDetail();
  }

  void _openDetail() {
    final overlay = Overlay.of(context);
    setState(() => _loadingDetail = true);
    // ignore: discarded_futures
    _refresh(includeTop: true);
    _overlay = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDetail,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(ctx).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 260,
                    maxWidth: 320,
                    maxHeight: 360,
                  ),
                  child: _DetailPanel(
                    loading: _loadingDetail && _top.isEmpty,
                    percent: _percent,
                    processes: _top,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    _restartTimer();
  }

  void _closeDetail() {
    _removeOverlay();
    if (mounted) setState(() {});
    _restartTimer();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final label = _percent == null ? '—%' : '$_percent%';
    final color = _percent == null
    ? Theme.of(context).hintColor
    : (_percent! >= 90
      ? Theme.of(context).colorScheme.error
      : Theme.of(context).colorScheme.onSurfaceVariant);


    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: 'メモリ使用率（5秒更新）。クリックで使用上位アプリ',
        child: InkWell(
          onTap: _toggleDetail,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'メモリ使用率'
                  '$label',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
      required this.loading,
      required this.percent,
      required this.processes,
  });

  final bool loading;
  final int? percent;
  final List<CodingProcessMemory> processes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'メモリ使用 上位${CodingSystemMemory.topProcessLimit}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            percent == null ? '全体: —（2秒更新）' : '全体: $percent%（2秒更新）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 8),
          if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
          else if (processes.isEmpty)
          Text(
            '取得できませんでした',
            style: theme.textTheme.bodySmall,
          )
          else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: processes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = processes[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p.rssLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
