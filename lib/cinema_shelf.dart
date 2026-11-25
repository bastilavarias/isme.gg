import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';

/// Remember a row's cursor, but expand only the card with actual focus.
class CinemaShelf extends StatefulWidget {
  final String title;
  final List<Movie> movies;
  final ValueChanged<Movie> onHighlight, onOpen;
  final ValueChanged<bool>? onVertical;
  final VoidCallback? onRowFocus;
  const CinemaShelf({super.key, required this.title, required this.movies,
    required this.onHighlight, required this.onOpen, this.onVertical, this.onRowFocus});
  @override CinemaShelfState createState() => CinemaShelfState();
}

class CinemaShelfState extends State<CinemaShelf> {
  static const height = 204.0, narrow = 132.0, wide = 348.0, gap = 10.0, gutter = 40.0;
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusNode> _nodes = {};
  String? _remembered, _focused;
  int _revision = 0;
  int get _cursor {
    final index = widget.movies.indexWhere((m) => m.id == _remembered);
    return index < 0 ? 0 : index;
  }
  bool get hasActiveFocus => _focused != null;
  Movie? get _selected => _focused == null ? null :
      widget.movies.where((m) => m.id == _focused).firstOrNull;
  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero : const Duration(milliseconds: 240);
  FocusNode _node(Movie movie) => _nodes.putIfAbsent(movie.id,
      () => FocusNode(debugLabel: '${widget.title}: ${movie.title}'));
  double _expandedWidth(double viewport) =>
      (viewport - gutter * 2).clamp(narrow, wide).toDouble();

  void focusRemembered() {
    if (widget.movies.isEmpty) return;
    _focusIndex(_cursor);
  }

  void _focusIndex(int index) {
    if (index < 0 || index >= widget.movies.length) return;
    final node = _node(widget.movies[index]);
    if (node.context != null) { node.requestFocus(); return; }
    if (!_scroll.hasClients) return;
    final revision = ++_revision;
    final pos = _scroll.position;
    final offset = (index * (narrow + gap)).clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if (_motion == Duration.zero) { pos.jumpTo(offset); }
    else { pos.animateTo(offset, duration: _motion, curve: Curves.easeOutCubic); }
    Future<void>.delayed(_motion, () {
      if (!mounted || revision != _revision) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _revision && node.context != null) node.requestFocus();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      _focusIndex(_cursor + (key == LogicalKeyboardKey.arrowRight ? 1 : -1));
      return KeyEventResult.handled;
    }
    if (widget.onVertical != null &&
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      widget.onVertical!(key == LogicalKeyboardKey.arrowDown);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _reveal(int index, int revision) {
    if (!mounted || revision != _revision || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final left = gutter + index * (narrow + gap);
    final right = left + _expandedWidth(pos.viewportDimension);
    var offset = pos.pixels;
    if (left < offset + 12) { offset = left - 12; }
    else if (right > offset + pos.viewportDimension - 12) {
      offset = right - pos.viewportDimension + 12;
    }
    offset = offset.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if ((offset - pos.pixels).abs() < 1) return;
    if (_motion == Duration.zero) { pos.jumpTo(offset); }
    else { pos.animateTo(offset, duration: _motion, curve: Curves.easeOutCubic); }
  }

  void _highlight(Movie movie, int index, bool focused) {
    if (!mounted) return;
    if (!focused) {
      if (_focused == movie.id) { _revision++; setState(() => _focused = null); }
      return;
    }
    final revision = ++_revision;
    setState(() { _remembered = movie.id; _focused = movie.id; });
    widget.onHighlight(movie);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(index, revision));
  }

  @override void dispose() {
    _revision++;
    _scroll.dispose();
    for (final node in _nodes.values) { node.dispose(); }
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    final selected = _selected;
    final duration = _motion;
    return Focus(onKeyEvent: _keys, canRequestFocus: false,
      onFocusChange: (focused) { if (focused) widget.onRowFocus?.call(); },
      child: Padding(padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: gutter),
            child: Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          const SizedBox(height: 10),
          SizedBox(height: height, child: LayoutBuilder(builder: (context, constraints) {
            final expandedWidth = _expandedWidth(constraints.maxWidth);
            return ListView.builder(controller: _scroll, scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: gutter), cacheExtent: expandedWidth + narrow,
              itemCount: widget.movies.length,
              itemBuilder: (context, index) {
                final movie = widget.movies[index];
                final expanded = movie.id == _focused;
                return Padding(key: ValueKey(movie.id), padding: const EdgeInsets.only(right: gap),
                  child: AnimatedContainer(key: ValueKey('size-${movie.id}'),
                    width: expanded ? expandedWidth : narrow, duration: duration, curve: Curves.easeOutCubic,
                    onEnd: () { if (expanded && _focused == movie.id) _reveal(index, _revision); },
                    child: RemoteTile(label: movie.title, focusNode: _node(movie),
                      onPressed: () => widget.onOpen(movie), revealOnFocus: false,
                      onFocusChanged: (value) => _highlight(movie, index, value),
                      child: Stack(fit: StackFit.expand, children: [
                        AnimatedSwitcher(duration: duration,
                          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand,
                            children: [...previous, if (current != null) current]),
                          child: CinemaArt(expanded ? movie.art : movie.poster,
                            key: ValueKey(expanded ? movie.art : movie.poster),
                            cacheWidth: expanded ? 768 : 360)),
                        if (expanded || movie.poster.isEmpty) const DecoratedBox(decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xDD000000)], stops: [.45, 1]))),
                        if (expanded || movie.poster.isEmpty) Positioned(left: 10, right: 10, bottom: 10,
                          child: Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: expanded ? 23 : 14, fontWeight: FontWeight.w700))),
                        if (expanded) const Positioned(top: 10, right: 10,
                          child: Icon(Icons.play_circle_fill, size: 26, color: CinemaColors.ink)),
                      ]))));
              });
          })),
          AnimatedSize(duration: duration, curve: Curves.easeOutCubic, alignment: Alignment.topLeft,
            onEnd: () { if (_focused != null) widget.onRowFocus?.call(); },
            child: selected == null ? const SizedBox(width: double.infinity) :
              Padding(padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
                child: AnimatedSwitcher(duration: duration,
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current]),
                  child: SizedBox(key: ValueKey(selected.id), width: 580, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(selected.metadata, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CinemaColors.muted)),
                      if (selected.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text(selected.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 1.35))),
                    ]))))),
        ])));
  }
}
