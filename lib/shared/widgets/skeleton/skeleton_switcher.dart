import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cover_reveal.dart';
import 'launch_entrance.dart';
import 'painted_when.dart';
import 'skeleton.dart';
import 'skeleton_reveal.dart';
import 'snapshot_sweep.dart';

/// 骨架與真實內容之間的切換：資料到了以骨架換場（[SkeletonReveal] 的方式
/// 與時長）換成內容；重新載入時骨架也照同樣的方式
/// 與時長長回來。
///
/// 預設兩者都撐滿父層（整頁內容區）；可收縮的面板以 [fit] 保留自然高度。
/// [builder] 只在載入完成後才呼叫。
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.builder,
    this.waitForCovers,
    this.entrance,
    this.backdrop,
    this.onRevealed,
    this.fit = StackFit.expand,
  });

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  /// 骨架換成內容、換場播完的那一刻（內容已經照常排好）。
  final VoidCallback? onRevealed;

  /// 頁面撐滿內容區；依內容收縮的面板沿用自然高度。
  final StackFit fit;

  /// 骨架與內容後面的實色（通常是頁面底色）。給了的話換場只遮骨架一層：
  /// 骨架墊著這個顏色蓋在照常畫出的內容上，由左而右退開；內容不再套動畫
  /// 遮罩、不另開離屏圖層，換場的每一格少合成一張整區大的圖層（ADR 0029）。
  /// 換到一半時是骨架覆蓋著淡出，比兩層交叉淡換的骨架稍微明顯一點。
  /// 後面不是單一實色（例如半透明、漸層或圖片）時留 null，兩層各自淡入淡出。
  final Color? backdrop;

  /// 給了的話，資料到了先在骨架底下建好內容，照這個方式等畫面上的封面
  /// （[CoverReveal]），再連同封面一次換場；不會先出現空白的書卡、封面再
  /// 一張張浮出來。null 時不等。
  final CoverWait? waitForCovers;

  /// 開 App 的進場（書架的骨架，見 [LaunchEntrance]）：骨架照它的進度、以
  /// 骨架換場的方式出現；這段期間資料到了也先不建內容、不換場，播完才接著
  /// 做（ADR 0018）。第一次換成內容時整個主頁面一起照兩張定格畫面換場
  /// （[LaunchEntranceMotion.reveal]，ADR 0031）。null 時骨架一開始就在。
  final LaunchEntranceMotion? entrance;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.loading ? 0 : 1,
  )..addStatusListener(_onStatus);

  /// 內容出現的進度（經過的時間比例，曲線由 [SkeletonReveal] 套）。
  late final CurvedAnimation _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _content = _controller;
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  void _onStatus(AnimationStatus status) {
    setState(() {});
    // 定格換場時內容一下就換好，換場播完才算出現。
    if (status.isCompleted && !widget.loading && _snapshotting == null) {
      widget.onRevealed?.call();
    }
  }

  /// 正在播的定格換場；換場播完或重新載入時清掉。
  SnapshotSweepController? _snapshotting;

  /// 這一次換進來的是哪一層：換成內容，或重新載入時長回骨架。
  SkeletonRevealSide _incoming = SkeletonRevealSide.content;

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  /// 淡入前等封面的那一輪；等完或重新載入就換掉。
  CoverReveal? _reveal;

  /// 開 App 第一次換場前，資料到了、正在等骨架收住呼吸
  /// （[LaunchEntranceMotion.settleBreath]）；這段期間當作還在載入，內容不建。
  Future<void>? _resting;

  /// 重新載入、淡回骨架時，淡出中的內容沿用上一次建好的樣子。
  Widget? _lastContent;

  /// [_lastContent] 是照哪一個 widget 與哪一輪等封面建的。
  SkeletonSwitcher? _contentFor;
  CoverReveal? _contentReveal;

  /// 骨架還在進場：這段期間當作還在載入。
  bool get _entering {
    final entrance = widget.entrance;
    return entrance != null && !entrance.skeleton.isCompleted;
  }

  @override
  void initState() {
    super.initState();
    widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    // 一開始就是內容（沒有骨架可換）時，進場的按鈕也直接到位。
    if (_controller.isCompleted) widget.entrance?.revealNow();
  }

  @override
  void didUpdateWidget(SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entrance, oldWidget.entrance)) {
      oldWidget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
      widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    }
    if (widget.loading == oldWidget.loading) return;
    _reveal = null;
    _resting = null;
    if (widget.loading) {
      // 定格換場還沒播完就要長回骨架：先換回真的畫面，從內容接著長回去。
      // 長完停時的準備做到一半的話放棄，骨架照常呼吸。
      _snapshotting?.finish();
      _snapshotting = null;
      widget.entrance?.donePreparing();
      _prepare(SkeletonRevealSide.skeleton);
      _controller.reverse();
    } else if (!_entering) {
      _onLoaded(duringBuild: true);
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {});
    if (!widget.loading) _onLoaded();
  }

  void _onLoaded({bool duringBuild = false}) {
    _controller.duration = const Duration(milliseconds: 150);
    if (duringBuild) {
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.loading) unawaited(_controller.forward());
      });
    } else {
      unawaited(_controller.forward(from: 0));
    }
    widget.entrance?.revealNow();
    widget.onRevealed?.call();
  }

  void _prepare(SkeletonRevealSide incoming) {
    _incoming = incoming;
    _sweep = false;
    _controller
      ..duration = const Duration(milliseconds: 150)
      ..reverseDuration = Duration.zero;
  }

  @override
  void dispose() {
    widget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
    _snapshotting?.finish();
    widget.entrance?.donePreparing();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      final backdrop = widget.backdrop;
      const indicator = _DelayedLoadingIndicator();
      if (backdrop == null) {
        return indicator;
      }
      return ColoredBox(
        color: backdrop,
        child: widget.fit == StackFit.expand
            ? const SizedBox.expand(child: indicator)
            : indicator,
      );
    }
    if (!identical(_contentFor, widget)) {
      _contentFor = widget;
      _contentReveal = null;
      _lastContent = Builder(builder: widget.builder);
    }
    return FadeTransition(
      opacity: _fade,
      child: _lastContent!,
    );
  }
}

class _DelayedLoadingIndicator extends StatefulWidget {
  const _DelayedLoadingIndicator();

  @override
  State<_DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<_DelayedLoadingIndicator> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CupertinoActivityIndicator(),
      ),
    );
  }
}