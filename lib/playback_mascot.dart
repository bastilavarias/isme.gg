import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design.dart';

enum IsmePlaybackPose { finding, connecting, buffering, starting, retrying, failed, closing }

IsmePlaybackPose playbackPose({required String phase, Object? nativeStatus,
    bool leaving = false, bool failed = false, int attempts = 0}) {
  if (leaving || phase == 'Stopping') return IsmePlaybackPose.closing;
  if (failed) return IsmePlaybackPose.failed;
  if (phase == 'Recovering playback') return IsmePlaybackPose.retrying;
  if (phase == 'Initializing player') return IsmePlaybackPose.starting;
  if (phase == 'Validating stream') return IsmePlaybackPose.connecting;
  if (phase == 'Buffering startup') return IsmePlaybackPose.buffering;
  return switch (nativeStatus) {
    'resolving' => IsmePlaybackPose.finding,
    'loading' => IsmePlaybackPose.connecting,
    'buffering' => IsmePlaybackPose.buffering,
    _ => attempts > 1 ? IsmePlaybackPose.retrying : IsmePlaybackPose.finding,
  };
}

/// Offline vector character. Animation is decorative and never drives progress.
class PlaybackMascot extends StatefulWidget {
  const PlaybackMascot({super.key, required this.pose, this.size = 150});
  final IsmePlaybackPose pose;
  final double size;

  @override
  State<PlaybackMascot> createState() => _PlaybackMascotState();
}

class _PlaybackMascotState extends State<PlaybackMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1600));

  void _sync() {
    final still = MediaQuery.disableAnimationsOf(context) ||
        widget.pose == IsmePlaybackPose.failed;
    if (still) {
      _loop.stop();
      _loop.value = 0;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlaybackMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pose != widget.pose) _sync();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(dimension: widget.size,
        child: CustomPaint(painter: _IsmePainter(widget.pose, _loop))),
    ),
  );
}

class _IsmePainter extends CustomPainter {
  _IsmePainter(this.pose, this.loop) : super(repaint: loop);
  final IsmePlaybackPose pose;
  final Animation<double> loop;

  static const fur = Color(0xFF101013);
  static const lightFur = Color(0xFF49484A);
  static const outline = Color(0xFF777477);
  static const innerEar = Color(0xFF2B2A2D);
  static const dark = Color(0xFF08080A);
  static const iris = Color(0xFF777477);
  static const collar = Color(0xFFFF8617);
  static const cream = Color(0xFFFFE3A0);
  static const white = CinemaColors.ink;
  static const accent = collar;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 240;
    canvas.save();
    canvas.translate((size.width - 240 * scale) / 2, (size.height - 240 * scale) / 2);
    canvas.scale(scale);
    final t = loop.value * 2 * math.pi;
    final wave = math.sin(t);
    Paint fill(Color color) => Paint()..color = color;
    Paint stroke(Color color, [double width = 2]) => Paint()
      ..color = color..style = PaintingStyle.stroke..strokeWidth = width
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    void oval(double x,double y,double rx,double ry,Color color,[bool edge = false]) {
      final rect = Rect.fromCenter(center: Offset(x,y),width: rx*2,height: ry*2);
      canvas.drawOval(rect,fill(color));
      if (edge) canvas.drawOval(rect,stroke(outline,1.6));
    }
    void line(double x,double y,double a,double b,Color color,[double width=2]) =>
      canvas.drawLine(Offset(x,y),Offset(a,b),stroke(color,width));
    void shape(Path p,Color color,[bool edge=false]) {
      canvas.drawPath(p,fill(color));
      if (edge) canvas.drawPath(p,stroke(outline,1.7));
    }
    void dot(double x,double y,double radius,Color color) =>
      canvas.drawCircle(Offset(x,y),radius,fill(color));

    final orbit=Rect.fromCircle(center:const Offset(120,115),radius:84);
    canvas.drawArc(orbit,3.92,1.58,false,stroke(accent,4));
    canvas.drawArc(orbit,.24,.64,false,stroke(accent,4));
    canvas.drawArc(orbit,2.25,.64,false,stroke(accent,4));
    oval(120,213,66,7, dark);
    final tail = Path()..moveTo(145,187)..quadraticBezierTo(191,198,194,162+wave*7)
      ..quadraticBezierTo(202,145+wave*7,207,158+wave*7)
      ..quadraticBezierTo(216,203,151,203)..close();
    shape(tail,fur,true);
    oval(120,174,38,36,fur,true);
    oval(93,193,22,19,fur,true);
    oval(146,193,22,19,fur,true);
    oval(107,202,12,11,lightFur,true);
    oval(133,202,12,11,lightFur,true);

    final tilt = switch(pose) {
      IsmePlaybackPose.finding => .10 * wave,
      IsmePlaybackPose.retrying => -.12 + .06*wave,
      IsmePlaybackPose.failed => -.13,
      IsmePlaybackPose.starting => .04*wave,
      _ => .025*wave,
    };
    canvas.save();
    canvas.translate(120,112);
    canvas.rotate(tilt);
    canvas.translate(-120,-112);
    // Continuous silhouette, tapered muzzle and swept ears match the orbital mark.
    final head=Path()..moveTo(98,63)
      ..cubicTo(80,46,59,52,35,29)..cubicTo(17,13,22,55,31,69)
      ..quadraticBezierTo(39,84,55,92)..quadraticBezierTo(60,108,77,114)
      ..cubicTo(84,120,83,139,101,151)..quadraticBezierTo(120,169,139,151)
      ..cubicTo(157,139,156,120,163,114)..quadraticBezierTo(180,108,185,92)
      ..quadraticBezierTo(201,84,209,69)..cubicTo(218,55,223,13,205,29)
      ..cubicTo(181,52,160,46,142,63)..quadraticBezierTo(120,55,98,63)..close();
    shape(head,fur);
    canvas.drawPath(head,stroke(accent,3.8));
    for(final sign in [-1.0,1.0]){
      canvas.save();canvas.translate(120,0);canvas.scale(sign,1);
      shape(Path()..moveTo(83,43)..quadraticBezierTo(66,57,48,57)
        ..lineTo(37,69)..lineTo(48,68)..lineTo(42,80)..lineTo(61,86)
        ..lineTo(53,93)..quadraticBezierTo(72,81,77,70)..close(),innerEar);
      shape(Path()..moveTo(11,70)..quadraticBezierTo(26,65,39,80)
        ..lineTo(27,74)..quadraticBezierTo(17,71,11,70)..close(),lightFur);
      shape(Path()..moveTo(12,98)..quadraticBezierTo(25,84,40,99)
        ..lineTo(42,108)..quadraticBezierTo(28,94,12,98)..close(),lightFur);
      canvas.restore();
    }
    shape(Path()..moveTo(124,111)..quadraticBezierTo(117,125,112,132)
      ..quadraticBezierTo(102,129,100,139)..quadraticBezierTo(105,155,122,155)
      ..quadraticBezierTo(142,153,142,141)..quadraticBezierTo(132,131,124,111)..close(),lightFur);
    for (final x in [96.0,144.0]) {
      oval(x,109,12,14,dark,true);
      final look = pose == IsmePlaybackPose.finding ? wave*3 : 0.0;
      oval(x+look,110,8,10,iris);
      oval(x+look,110,5.5,7,dark);
      dot(x+look-2,105,2.9,white);
      dot(x+look+3,114,1.2,white);
      canvas.drawArc(Rect.fromCenter(center:Offset(x,109),width:21,height:23),.75,1.25,false,stroke(outline,1.4));
    }
    shape(Path()..moveTo(109,126)..quadraticBezierTo(120,120,131,126)
      ..quadraticBezierTo(135,133,120,140)..quadraticBezierTo(105,133,109,126)..close(),dark);
    line(120,139,120,144,dark);
    if (pose == IsmePlaybackPose.starting) {
      shape(Path()..moveTo(109,144)..quadraticBezierTo(120,151,131,144)
        ..quadraticBezierTo(120,166,109,144)..close(),dark);
      oval(120,153,5,4,innerEar);
    } else {
      canvas.drawPath(Path()..moveTo(109,144)..quadraticBezierTo(114,149,120,144)
        ..quadraticBezierTo(126,149,131,144),stroke(dark,2));
    }
    canvas.restore();
    canvas.drawArc(Rect.fromCenter(center: const Offset(120,145),width:60,height:32),
      .12,math.pi-.24,false,stroke(collar,7));
    dot(120,168,8,collar);
    shape(Path()..moveTo(118,164)..lineTo(125,168)..lineTo(118,172)..close(),white);

    // Each pose has a distinct visual cue, independent of actual percentages.
    switch (pose) {
      case IsmePlaybackPose.finding:
        final x = 183 + wave*5;
        line(x+11,135,x+28,153,accent,7);
        canvas.drawCircle(Offset(x,124),17,stroke(white,4));
        canvas.drawArc(Rect.fromCircle(center:Offset(x,124),radius:11),3.5,1.2,false,stroke(accent,2));
        break;
      case IsmePlaybackPose.connecting:
        canvas.drawPath(Path()..moveTo(39,191)..cubicTo(9,179,14,144,37,145),stroke(accent,3));
        shape(Path()..moveTo(31,137)..lineTo(46,137)..lineTo(46,153)..lineTo(31,153)..close(),accent);
        line(35,137,35,129,white,2); line(42,137,42,129,white,2);
        for (var i=0;i<3;i++) {
          final r=9.0+i*6;
          canvas.drawArc(Rect.fromCircle(center:const Offset(194,124),radius:r),3.9,1.65,false,
            stroke((i+loop.value*3).floor().isEven?accent:outline,2.5));
        }
        dot(194,124,3,accent);
        break;
      case IsmePlaybackPose.buffering:
        for(var i=0;i<3;i++) {
          final y=177.0-i*14 + math.sin(t+i)*4;
          final r=RRect.fromRectAndRadius(Rect.fromLTWH(182+i*7.0,y,17,12),const Radius.circular(3));
          canvas.drawRRect(r,fill(i==1?accent:lightFur));
          canvas.drawRRect(r,stroke(outline,1.3));
        }
        break;
      case IsmePlaybackPose.starting:
        shape(Path()..moveTo(176,171)..lineTo(207,171)..lineTo(202,204)..lineTo(181,204)..close(),cream);
        line(185,173,188,201,collar,4); line(198,173,196,201,collar,4);
        for(final p in [const Offset(180,169),const Offset(190,163),const Offset(200,166),const Offset(207,171)]) {
          dot(p.dx,p.dy+wave*2,6,cream);
        }
        break;
      case IsmePlaybackPose.retrying:
        canvas.drawArc(Rect.fromCircle(center:const Offset(192,124),radius:19),t,math.pi*1.55,false,stroke(accent,4));
        final a=t+math.pi*1.55;
        final end=Offset(192+19*math.cos(a),124+19*math.sin(a));
        canvas.save();canvas.translate(end.dx,end.dy);canvas.rotate(a+math.pi/2);
        shape(Path()..moveTo(7,0)..lineTo(-5,-6)..lineTo(-5,6)..close(),accent);
        canvas.restore();
        break;
      case IsmePlaybackPose.failed:
        canvas.drawPath(Path()..moveTo(184,112)..cubicTo(184,98,205,99,205,112)
          ..quadraticBezierTo(205,118,195,122)..lineTo(195,128),stroke(accent,4));
        dot(195,137,2.7,accent);
        break;
      case IsmePlaybackPose.closing:
        for(var i=0;i<3;i++) {dot(180+i*11.0,130,3,outline);}
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IsmePainter oldDelegate) =>
      oldDelegate.pose != pose || oldDelegate.loop != loop;
}
