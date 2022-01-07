import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/map/map.dart';
import 'package:latlong2/latlong.dart';

class CurvedPolylineMapPlugin extends MapPlugin {
  @override
  bool supportsLayer(LayerOptions options) =>
      options is CurvedPolylineLayerOptions;

  @override
  Widget createLayer(
      LayerOptions options, MapState mapState, Stream<Null> stream) {
    return CurvedPolylineLayer(
        options as CurvedPolylineLayerOptions, mapState, stream);
  }
}

class CurvedPolylineLayerOptions extends LayerOptions {
  final List<CurvedPolyline> polylines;
  final Animation<double>? animation;
  final bool polylineCulling;

  CurvedPolylineLayerOptions({
    Key? key,
    this.polylines = const [],
    this.polylineCulling = false,
    this.animation,
    Stream<Null>? rebuild,
  }) : super(key: key, rebuild: rebuild) {
    if (polylineCulling) {
      for (var polyline in polylines) {
        polyline.boundingBox =
            LatLngBounds.fromPoints([polyline.pointFrom, polyline.pointTo]);
      }
    }
  }
}

class CurvedPolyline {
  final LatLng pointFrom;
  final LatLng pointTo;
  final List<Offset> offsets = [];
  final double fixStrokeWidth;
  final double animatedStrokeWidth;
  final Color fixColor;
  final Color animatedColor;
  final double borderStrokeWidth;
  final Color? borderColor;
  final List<Color>? gradientColors;
  final List<double>? colorsStop;
  final bool isDotted;
  late final LatLngBounds boundingBox;

  CurvedPolyline({
    required this.pointFrom,
    required this.pointTo,
    this.fixStrokeWidth = 1.0,
    this.animatedStrokeWidth = 1.0,
    this.fixColor = const Color(0xFF00FF00),
    this.animatedColor = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.gradientColors,
    this.colorsStop,
    this.isDotted = false,
  });
}

class CurvedPolylineLayerWidget extends StatelessWidget {
  final CurvedPolylineLayerOptions options;

  CurvedPolylineLayerWidget({Key? key, required this.options})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mapState = MapState.maybeOf(context)!;
    return CurvedPolylineLayer(options, mapState, mapState.onMoved);
  }
}

class CurvedPolylineLayer extends StatelessWidget {
  final CurvedPolylineLayerOptions polylineOpts;
  final MapState map;
  final Stream<Null>? stream;

  CurvedPolylineLayer(this.polylineOpts, this.map, this.stream)
      : super(key: polylineOpts.key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size);
      },
    );
  }

  Widget _build(BuildContext context, Size size) {
    return StreamBuilder<void>(
      stream: stream, // a Stream<void> or null
      builder: (BuildContext context, _) {
        var polylines = <Widget>[];

        for (var polylineOpt in polylineOpts.polylines) {
          polylineOpt.offsets.clear();

          if (polylineOpts.polylineCulling &&
              !polylineOpt.boundingBox.isOverlapping(map.bounds)) {
            // skip this polyline as it's offscreen
            continue;
          }

          _fillOffsets(polylineOpt.offsets, [polylineOpt.pointFrom,polylineOpt.pointTo]);

          polylines.add(CustomPaint(
            painter: CurvedPolylinePainter(polylineOpt, polylineOpts.animation),
            size: size,
          ));
        }

        return Container(
          child: Stack(
            children: polylines,
          ),
        );
      },
    );
  }

  void _fillOffsets(final List<Offset> offsets, final List<LatLng> points) {
    for (var i = 0, len = points.length; i < len; ++i) {
      var point = points[i];

      var pos = map.project(point);
      pos = pos.multiplyBy(map.getZoomScale(map.zoom, map.zoom)) -
          map.getPixelOrigin();
      offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
      if (i > 0) {
        offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
      }
    }
  }
}

class CurvedPolylinePainter extends CustomPainter {
  final CurvedPolyline polylineOpt;
  Animation<double>? animation;

  CurvedPolylinePainter(this.polylineOpt, this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (polylineOpt.offsets.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final paint = Paint()
      ..strokeWidth = polylineOpt.fixStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.srcOver;

    if (polylineOpt.gradientColors == null) {
      paint.color = polylineOpt.fixColor;
    } else {
      polylineOpt.gradientColors!.isNotEmpty
          ? paint.shader = _paintGradient()
          : paint.color = polylineOpt.fixColor;
    }

    Paint? filterPaint;
    if (polylineOpt.borderColor != null) {
      filterPaint = Paint()
        ..color = polylineOpt.borderColor!.withAlpha(255)
        ..strokeWidth = polylineOpt.fixStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.dstOut;
    }

    final borderPaint = polylineOpt.borderStrokeWidth > 0.0
        ? (Paint()
          ..color = polylineOpt.borderColor ?? Color(0x00000000)
          ..strokeWidth =
              polylineOpt.fixStrokeWidth + polylineOpt.borderStrokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver)
        : null;
    var radius = paint.strokeWidth / 2;
    var borderRadius = (borderPaint?.strokeWidth ?? 0) / 2;
    if (polylineOpt.isDotted) {
      var spacing = polylineOpt.fixStrokeWidth * 1.5;
      canvas.saveLayer(rect, Paint());
      if (borderPaint != null && filterPaint != null) {
        _paintDottedLine(
            canvas, polylineOpt.offsets, borderRadius, spacing, borderPaint);
        _paintDottedLine(
            canvas, polylineOpt.offsets, radius, spacing, filterPaint);
      }
      _paintDottedLine(canvas, polylineOpt.offsets, radius, spacing, paint);
      canvas.restore();
    } else {
      paint.style = PaintingStyle.stroke;
      canvas.saveLayer(rect, Paint());
      if (borderPaint != null && filterPaint != null) {
        borderPaint.style = PaintingStyle.stroke;
        _paintLine(canvas, polylineOpt.offsets, borderPaint, animation?.value);
        filterPaint.style = PaintingStyle.stroke;
        _paintLine(canvas, polylineOpt.offsets, filterPaint, animation?.value);
      }
      _paintLine(canvas, polylineOpt.offsets, paint, animation?.value);
      canvas.restore();
    }
  }

  void _paintDottedLine(Canvas canvas, List<Offset> offsets, double radius,
      double stepLength, Paint paint) {
    final path = ui.Path();
    var startDistance = 0.0;
    for (var i = 0; i < offsets.length - 1; i++) {
      var o0 = offsets[i];
      var o1 = offsets[i + 1];
      var totalDistance = _dist(o0, o1);
      var distance = startDistance;
      while (distance < totalDistance) {
        var f1 = distance / totalDistance;
        var f0 = 1.0 - f1;
        var offset = Offset(o0.dx * f0 + o1.dx * f1, o0.dy * f0 + o1.dy * f1);
        path.addOval(Rect.fromCircle(center: offset, radius: radius));
        distance += stepLength;
      }
      startDistance = distance < totalDistance
          ? stepLength - (totalDistance - distance)
          : distance - totalDistance;
    }
    path.addOval(
        Rect.fromCircle(center: polylineOpt.offsets.last, radius: radius));
    canvas.drawPath(path, paint);
  }

  void _paintLine(Canvas canvas, List<Offset> offsets, Paint paint,
      double? animationPercent) {
    if (offsets.isNotEmpty) {
      final path = ui.Path()..moveTo(offsets[0].dx, offsets[0].dy);
      // path.quadraticBezierTo(offsets[0].dx / 2, offsets[0].dy, offsets[0].dy, offsets[0].dx / 2);


      var dx0 = offsets[0].dx;
      var dy0 = offsets[0].dy;
      var dy1 = offsets[1].dy;
      var dx1 = offsets[1].dx;
      var dy01 = (offsets[0] - offsets[1]).dy;
      var dx01 = (offsets[0] - offsets[1]).dx;

      path.quadraticBezierTo(
          ((dx0 + dx1 - dy01) / 2), ((dy0 + dy1 + dx01) / 2), dx1, dy1);
      ui.Path? p;
      canvas.drawPath(path, paint);
      if (animationPercent != null) {
        p = createAnimatedPath(path, animationPercent);
      }
      paint.color = polylineOpt.animatedColor;
      paint.strokeWidth = polylineOpt.animatedStrokeWidth;
      canvas.drawPath(p ?? path, paint);
    }
  }

  ui.Path createAnimatedPath(
    ui.Path originalPath,
    double animationPercent,
  ) {
    // ComputeMetrics can only be iterated once!
    final totalLength = originalPath
        .computeMetrics()
        .fold(0.0, (double prev, ui.PathMetric metric) => prev + metric.length);

    final currentLength = totalLength * animationPercent;

    return extractPathUntilLength(originalPath, currentLength);
  }

  ui.Path extractPathUntilLength(
    ui.Path originalPath,
    double length,
  ) {
    var currentLength = 0.0;

    final path = new ui.Path();

    var metricsIterator = originalPath.computeMetrics().iterator;

    while (metricsIterator.moveNext()) {
      var metric = metricsIterator.current;

      var nextLength = currentLength + metric.length;

      final isLastSegment = nextLength > length;
      if (isLastSegment) {
        final remainingLength = length - currentLength;
        final pathSegment = metric.extractPath(0.0, remainingLength);

        path.addPath(pathSegment, Offset.zero);
        break;
      } else {
        // There might be a more efficient way of extracting an entire path
        final pathSegment = metric.extractPath(0.0, metric.length);
        path.addPath(pathSegment, Offset.zero);
      }

      currentLength = nextLength;
    }

    return path;
  }

  ui.Gradient _paintGradient() => ui.Gradient.linear(polylineOpt.offsets.first,
      polylineOpt.offsets.last, polylineOpt.gradientColors!, _getColorsStop());

  List<double>? _getColorsStop() => (polylineOpt.colorsStop != null &&
          polylineOpt.colorsStop!.length == polylineOpt.gradientColors!.length)
      ? polylineOpt.colorsStop
      : _calculateColorsStop();

  List<double> _calculateColorsStop() {
    final colorsStopInterval = 1.0 / polylineOpt.gradientColors!.length;
    return polylineOpt.gradientColors!
        .map((gradientColor) =>
            polylineOpt.gradientColors!.indexOf(gradientColor) *
            colorsStopInterval)
        .toList();
  }

  @override
  bool shouldRepaint(CurvedPolylinePainter other) => false;
}

double _dist(Offset v, Offset w) {
  return sqrt(_dist2(v, w));
}

double _dist2(Offset v, Offset w) {
  return _sqr(v.dx - w.dx) + _sqr(v.dy - w.dy);
}

double _sqr(double x) {
  return x * x;
}
