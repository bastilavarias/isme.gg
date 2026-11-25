import 'package:flutter/material.dart';
import 'design.dart';
import 'engine.dart';

/// A TV-only rail with one remembered expanded card and a stable row height.
/// Scrolling is driven by focus, not by an autoplay timer.
class CinemaShelf extends StatefulWidget {
  final String title;
  final List<Movie> movies;
  final ValueChanged<Movie> onHighlight, onOpen;
  const CinemaShelf({super.key, required this.title, required this.movies,
    required this.onHighlight, required this.onOpen});
  @override
  State<CinemaShelf> createState() => _CinemaShelfState();
}
class _CinemaShelfState extends State<CinemaShelf> {
  static const height = 204.0, narrow = 132.0, wide = 348.0, gap = 10.0, gutter = 40.0;
  final ScrollController _scroll = ScrollController();
  String? _selectedId;
  int _revision = 0;
  int get _active {
    final index = widget.movies.indexWhere((movie) => movie.id == _selectedId);
    return index < 0 ? 0 : index;
  }
  Duration get _motion => MediaQuery.disableAnimationsOf(context)
    ? Duration.zero : const Duration(milliseconds: 240);

  void _reveal(int index, int revision, {bool settle = false}) {
    if (!mounted || revision != _revision || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final width = _expandedWidth(pos.viewportDimension);
    // All earlier tiles are narrow in the final layout.
    final left = gutter + index * (narrow + gap);
    final right = left + width;
    final inset = 12.0;
    var offset = pos.pixels;
    if (left < offset + inset) {
      offset = left - inset;
    } else if (right > offset + pos.viewportDimension - inset) {
      offset = right - pos.viewportDimension + inset;
    }
    offset = offset.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if ((offset - pos.pixels).abs() < 1) return;
    if (_motion == Duration.zero || settle) {
      pos.jumpTo(offset);
    } else {
      pos.animateTo(offset, duration: _motion, curve: Curves.easeOutCubic);
    }
  }

  double _expandedWidth(double viewport) =>
      (viewport - gutter * 2).clamp(narrow, wide).toDouble();

  void _highlight(int index) {
    if (index >= widget.movies.length) return;
    final movie = widget.movies[index];
    final revision = ++_revision;
    setState(() => _selectedId = movie.id);
    widget.onHighlight(movie);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revision) return;
      _reveal(index, revision);
    });
  }

  @override
  void dispose() {
    _revision++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final duration = _motion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: gutter),
          child: Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        const SizedBox(height: 10),
        SizedBox(height: height, child: LayoutBuilder(builder: (context, constraints) {
          final expandedWidth = _expandedWidth(constraints.maxWidth);
          return ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: gutter),
            cacheExtent: expandedWidth + narrow,
            itemCount: widget.movies.length,
            itemBuilder: (context, index) {
              final movie = widget.movies[index];
              final expanded = index == active;
              final revision = _revision;
              return Padding(
                key: ValueKey(movie.id),
                padding: const EdgeInsets.only(right: gap),
                child: AnimatedContainer(
                  key: ValueKey('size-${movie.id}'),
                  width: expanded ? expandedWidth : narrow,
                  duration: duration, curve: Curves.easeOutCubic,
                  onEnd: () {
                    if (expanded && revision == _revision) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _reveal(index, revision, settle: true);
                      });
                    }
                  },
                  child: RemoteTile(
                    label: movie.title,
                    onPressed: () => widget.onOpen(movie),
                    onFocused: () => _highlight(index),
                    revealOnFocus: false,
                    child: Stack(fit: StackFit.expand, children: [
                      AnimatedSwitcher(
                        duration: duration,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand, children: [
                            ...previous, if (current != null) current,
                          ]),
                        child: CinemaArt(
                          expanded ? movie.art : movie.poster,
                          key: ValueKey(expanded ? movie.art : movie.poster),
                          cacheWidth: expanded ? 768 : 360,
                        ),
                      ),
                      const DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter,
                          end: Alignment.bottomCenter, colors: [
                            Colors.transparent, Colors.transparent, Color(0xDD000000),
                          ], stops: [0, .38, 1]))),
                      Positioned(left: 10, right: 10, bottom: 10,
                        child: AnimatedSwitcher(duration: duration,
                          layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
                          child: Text(movie.title, key: ValueKey(expanded),
                            maxLines: expanded ? 2 : 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: expanded ? 23 : 14,
                              fontWeight: expanded ? FontWeight.w800 : FontWeight.w500)))),
                      if (expanded) const Positioned(top: 10, right: 10,
                        child: Icon(Icons.play_circle_fill, size: 26, color: CinemaColors.ink)),
                    ]),
                  ),
                ),
              );
            },
          );
        })),
      ]),
    );
  }
}
