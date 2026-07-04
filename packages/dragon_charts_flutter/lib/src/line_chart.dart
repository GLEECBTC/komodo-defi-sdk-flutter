import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:dragon_charts_flutter/src/chart_data_transform.dart';
import 'package:dragon_charts_flutter/src/chart_tooltip.dart';
import 'package:dragon_charts_flutter/src/marker_selection_strategies/marker_selection_strategies.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ChartExtent {
  @Deprecated(
    'Use the named constructors instead. '
    'This constructor will be removed in the next release.',
  )
  ChartExtent({
    this.auto = true,
    double padding = 0.1,
    this.min,
    this.max,
  }) : paddingPortion = padding;

  const ChartExtent.withBounds({
    required this.min,
    required this.max,
  }) : auto = false,
       paddingPortion = 0;

  const ChartExtent.tight({this.paddingPortion = 0})
    : auto = true,
      min = null,
      max = null;

  final bool auto;
  final double paddingPortion;
  final double? min;
  final double? max;
}

/// A customizable and animated line chart widget for Flutter.
///
/// The [LineChart] class allows you to plot multiple data series with options
/// for custom tooltips and smooth animations when data points are added or
/// removed.
///
/// Example usage:
/// ```dart
/// LineChart(
///   elements: [
///     ChartGridLines(isVertical: false, count: 5),
///     ChartAxisLabels(
///       isVertical: true, count: 5, labelBuilder: (value) => value.toStringAsFixed(2),
///     ),
///     ChartAxisLabels(
///       isVertical: false, count: 5, labelBuilder: (value) => value.toStringAsFixed(2),
///     ),
///     ChartDataSeries(
///       data: [ChartData(x: 1.0, y: 2.0)],
///       color: Colors.blue,
///     ),
///     ChartDataSeries(
///       data: [ChartData(x: 1.0, y: 4.0)],
///       color: Colors.red,
///       lineType: LineType.bezier,
///     ),
///   ],
///   tooltipBuilder: (context, dataPoints, dataColors) {
///     return YourTooltipWidget(
///       dataPoints: dataPoints,
///       dataColors: dataColors,
///     );
///   },
///   backgroundColor: Colors.white,
/// )
/// ```
class LineChart extends StatefulWidget {
  /// Creates a [LineChart] widget.
  ///
  /// The [elements] and [tooltipBuilder] are required. The [animationDuration],
  /// [domainExtent], [rangeExtent], and [backgroundColor] have default values.
  const LineChart({
    required this.elements,
    this.tooltipBuilder,
    this.animationDuration = const Duration(milliseconds: 500),
    this.domainExtent = const ChartExtent.tight(),
    this.rangeExtent = const ChartExtent.tight(paddingPortion: 0.1),
    this.backgroundColor = Colors.black,
    this.padding = const EdgeInsets.all(32),
    this.markerSelectionStrategy,
    super.key,
  });

  /// The list of elements to be rendered in the chart.
  ///
  /// This list typically includes instances of [ChartDataSeries],
  /// [ChartGridLines], and [ChartAxisLabels].
  final List<ChartElement> elements;

  /// The duration of the animation when the chart updates.
  ///
  /// The default value is 500 milliseconds.
  final Duration animationDuration;

  /// A builder function to create custom tooltips for data points.
  ///
  /// If not provided, a default tooltip will be used.
  final Widget Function(BuildContext, List<ChartData>, List<Color>)?
  tooltipBuilder;

  /// The extent of the domain (x-axis) of the chart.
  ///
  /// This can be used to control the automatic scaling and padding of the domain.
  final ChartExtent domainExtent;

  /// The extent of the range (y-axis) of the chart.
  ///
  /// This can be used to control the automatic scaling and padding of the range.
  final ChartExtent rangeExtent;

  /// The background color of the chart.
  ///
  /// The default value is black.
  final Color backgroundColor;

  /// The padding around the chart to accommodate labels and other elements.
  ///
  /// The default value is 30.0 on all sides.
  final EdgeInsets padding;

  /// The strategy to use for selecting markers on the chart.
  ///
  /// This parameter is optional. If not specified, no marker selection or painting will be done.
  ///
  /// Current available strategies are:
  /// - [CartesianSelectionStrategy]
  /// - [PointSelectionStrategy]
  ///
  /// TODO: Consider adding a way to create custom marker selection strategies
  /// and in general, a way to create custom elements.
  final MarkerSelectionStrategy? markerSelectionStrategy;

  @override
  _LineChartState createState() => _LineChartState();
}

class _LineChartState extends State<LineChart>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();
  Offset? _hoverPosition;
  List<ChartData>? _highlightedData;
  List<Offset>? _highlightedPoints;
  List<Color> _highlightedColors = [];
  late AnimationController _controller;
  late Animation<double> _animation;
  Offset? _globalHoverPosition;

  List<ChartElement> oldElements = [];
  List<ChartElement> currentElements = [];

  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  double minY = double.infinity;
  double maxY = double.negativeInfinity;

  late Animation<double> minXAnimation;
  late Animation<double> maxXAnimation;
  late Animation<double> minYAnimation;
  late Animation<double> maxYAnimation;

  final GlobalKey _chartKey = GlobalKey();
  Size? _tooltipSize;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            oldElements = List.from(widget.elements);
          });
        }
      });
    oldElements = List.from(widget.elements);
    currentElements = List.from(widget.elements);
    _updateDomainRange();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant LineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `widget.elements` is rebuilt into a fresh list on every parent build, so
    // comparing by list identity (`!=`) always reported a change and restarted
    // the per-frame line animation on EVERY rebuild — even when the rebuild was
    // caused by something unrelated (a sibling bloc emitting, hover, theme).
    // That continuous re-animation is a dominant source of main-isolate load.
    // Only restart the animation when the plotted data actually changed.
    if (_seriesDataChanged(currentElements, widget.elements)) {
      setState(() {
        oldElements = List.from(currentElements);
        currentElements = List.from(widget.elements);
        _controller.reset();
        _updateDomainRange();
        _controller.forward();
        _clearHighlightedData();
      });
    } else {
      _updateDomainRange();
    }
  }

  /// Whether the plotted [ChartDataSeries] differ between [previous] and
  /// [next]. Non-series elements (grid lines, axis labels) do not animate, so
  /// they are ignored here. Runs in O(points), far cheaper than the animation
  /// it gates.
  static bool _seriesDataChanged(
    List<ChartElement> previous,
    List<ChartElement> next,
  ) {
    final a = previous.whereType<ChartDataSeries>().toList();
    final b = next.whereType<ChartDataSeries>().toList();
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final sa = a[i];
      final sb = b[i];
      if (sa.color != sb.color ||
          sa.strokeWidth != sb.strokeWidth ||
          sa.lineType != sb.lineType ||
          sa.nodeRadius != sb.nodeRadius ||
          sa.data.length != sb.data.length) {
        return true;
      }
      for (var j = 0; j < sa.data.length; j++) {
        if (sa.data[j].x != sb.data[j].x || sa.data[j].y != sb.data[j].y) {
          return true;
        }
      }
    }
    return false;
  }

  void _clearHighlightedData() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _overlayController.hide();
        setState(() {
          _hoverPosition = null;
          _highlightedData = null;
          _highlightedPoints = null;
          _highlightedColors = [];
        });
      }
    });
  }

  void _updateDomainRange() {
    var newMinX = double.infinity;
    var newMaxX = double.negativeInfinity;
    var newMinY = double.infinity;
    var newMaxY = double.negativeInfinity;

    for (final element in widget.elements) {
      if (element is ChartDataSeries) {
        for (final dataPoint in element.data) {
          final xValue = dataPoint.x;
          if (xValue < newMinX) newMinX = xValue;
          if (xValue > newMaxX) newMaxX = xValue;
          if (dataPoint.y < newMinY) newMinY = dataPoint.y;
          if (dataPoint.y > newMaxY) newMaxY = dataPoint.y;
        }
      }
    }

    if (!newMinX.isFinite ||
        newMaxX == double.negativeInfinity ||
        newMinY == double.infinity ||
        newMaxY == double.negativeInfinity) {
      newMinX = 0;
      newMaxX = 1;
      newMinY = 0;
      newMaxY = 1;
    }

    if (widget.domainExtent.auto) {
      final domainPaddingValue =
          (newMaxX - newMinX) * widget.domainExtent.paddingPortion;
      newMinX -= domainPaddingValue;
      newMaxX += domainPaddingValue;
    }
    newMinX = widget.domainExtent.min ?? newMinX;
    newMaxX = widget.domainExtent.max ?? newMaxX;

    if (widget.rangeExtent.auto) {
      final rangePaddingValue =
          (newMaxY - newMinY) * widget.rangeExtent.paddingPortion;
      newMinY -= rangePaddingValue;
      newMaxY += rangePaddingValue;
    }
    newMinY = widget.rangeExtent.min ?? newMinY;
    newMaxY = widget.rangeExtent.max ?? newMaxY;

    minXAnimation = Tween<double>(
      begin: minX,
      end: newMinX,
    ).animate(_controller);
    maxXAnimation = Tween<double>(
      begin: maxX,
      end: newMaxX,
    ).animate(_controller);
    minYAnimation = Tween<double>(
      begin: minY,
      end: newMinY,
    ).animate(_controller);
    maxYAnimation = Tween<double>(
      begin: maxY,
      end: newMaxY,
    ).animate(_controller);

    minX = newMinX;
    maxX = newMaxX;
    minY = newMinY;
    maxY = newMaxY;
  }

  late ChartDataTransform transform;

  bool get areAnimationsFinite =>
      minXAnimation.value.isFinite &&
      maxXAnimation.value.isFinite &&
      minYAnimation.value.isFinite &&
      maxYAnimation.value.isFinite;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        key: _chartKey,
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final chartSize = Size(
            size.width - widget.padding.horizontal,
            size.height - widget.padding.vertical,
          );

          if (!chartSize.isFinite || !areAnimationsFinite) {
            return Container();
          }

          transform = ChartDataTransform(
            minX: minXAnimation.value,
            maxX: maxXAnimation.value,
            minY: minYAnimation.value,
            maxY: maxYAnimation.value,
            width: chartSize.width,
            height: chartSize.height,
          );

          return Container(
            color: widget.backgroundColor,
            padding: widget.padding,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _hoverPosition = details.localPosition;
                });
              },
              onTapUp: (details) {
                _handleTap(details.localPosition);
              },
              onTapDown: (details) {
                _handleTap(details.localPosition);
              },
              child: MouseRegion(
                onHover: (details) {
                  _handleHover(details.localPosition);
                },
                onExit: (event) {
                  _overlayController.hide();
                  _clearHighlightedData();
                },
                child: OverlayPortal(
                  controller: _overlayController,
                  overlayChildBuilder: (context) {
                    if (_hoverPosition == null || _highlightedData == null) {
                      return Container();
                    }

                    return Stack(
                      children: [
                        if (_tooltipSize == null)
                          MeasureSize(
                            onSizeChange: (size) {
                              if (_tooltipSize != size) {
                                setState(() {
                                  _tooltipSize = size;
                                });
                              }
                            },
                            child: Material(
                              key: const Key('tooltip'),
                              color: Colors.transparent,
                              child: widget.tooltipBuilder != null
                                  ? widget.tooltipBuilder!(
                                      context,
                                      _highlightedData!,
                                      _highlightedColors,
                                    )
                                  : ChartTooltip(
                                      dataPoints: _highlightedData!,
                                      dataColors: _highlightedColors,
                                      backgroundColor: widget.backgroundColor,
                                    ),
                            ),
                          ),
                        if (_tooltipSize != null)
                          Positioned(
                            left: _calculateTooltipXPosition(
                              _globalHoverPosition!,
                              _tooltipSize!,
                              MediaQuery.of(context).size,
                            ),
                            top: _calculateTooltipYPosition(
                              _globalHoverPosition!,
                              _tooltipSize!,
                              MediaQuery.of(context).size,
                            ),
                            child: Material(
                              key: const Key('tooltip'),
                              color: Colors.transparent,
                              child: widget.tooltipBuilder != null
                                  ? widget.tooltipBuilder!(
                                      context,
                                      _highlightedData!,
                                      _highlightedColors,
                                    )
                                  : ChartTooltip(
                                      dataPoints: _highlightedData!,
                                      dataColors: _highlightedColors,
                                      backgroundColor: widget.backgroundColor,
                                    ),
                            ),
                          ),
                      ],
                    );
                  },
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final animatedElements = <ChartElement>[];
                      for (var i = 0; i < currentElements.length; i++) {
                        if (currentElements[i] is ChartDataSeries &&
                            oldElements[i] is ChartDataSeries) {
                          animatedElements.add(
                            (oldElements[i] as ChartDataSeries).animateTo(
                              currentElements[i] as ChartDataSeries,
                              _animation.value,
                              minYAnimation.value,
                            ),
                          );
                        } else {
                          animatedElements.add(currentElements[i]);
                        }
                      }
                      return CustomPaint(
                        key: const Key('chart_custom_paint'),
                        willChange: !_animation.isCompleted,
                        painter: _LineChartPainter(
                          elements: animatedElements,
                          transform: transform,
                          highlightedPoints: _highlightedPoints,
                          highlightedColors: _highlightedColors,
                          animation: _animation.value,
                          markerSelectionStrategy:
                              widget.markerSelectionStrategy,
                          hoverPosition: _hoverPosition,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _updateHighlightedData(
    List<ChartData> highlightedData,
    List<Offset> highlightedPoints,
    List<Color> highlightedColors,
  ) {
    setState(() {
      _highlightedData = highlightedData;
      _highlightedPoints = highlightedPoints;
      _highlightedColors = highlightedColors;
    });
    if (highlightedData.isNotEmpty) {
      _overlayController.show();
    } else {
      _overlayController.hide();
      _clearHighlightedData();
    }
  }

  void _handleHover(Offset localPosition) {
    if (widget.markerSelectionStrategy != null) {
      final box = context.findRenderObject()! as RenderBox;
      final globalPosition = box.localToGlobal(localPosition);
      final result = widget.markerSelectionStrategy!.handleHover(
        localPosition,
        transform,
        widget.elements,
      );
      setState(() {
        _hoverPosition = localPosition;
        _globalHoverPosition = globalPosition; // Store the global position
        _highlightedData = result.$1; // data
        _highlightedPoints = result.$2; // points
        _highlightedColors = result.$3; // colors
      });
      if (result.$1.isNotEmpty) {
        _overlayController.show();
      } else {
        _overlayController.hide();
      }
    }
  }

  void _handleTap(Offset localPosition) {
    if (widget.markerSelectionStrategy != null) {
      final box = context.findRenderObject()! as RenderBox;
      final globalPosition = box.localToGlobal(localPosition);
      final result = widget.markerSelectionStrategy!.handleTap(
        localPosition,
        transform,
        widget.elements,
      );
      setState(() {
        _hoverPosition = localPosition;
        _globalHoverPosition = globalPosition; // Store the global position
        _highlightedData = result.$1; // data
        _highlightedPoints = result.$2; // points
        _highlightedColors = result.$3; // colors
      });
      if (result.$1.isNotEmpty) {
        _overlayController.show();
      } else {
        _overlayController.hide();
      }
    } else {
      _clearHighlightedData();
    }
  }

  double _calculateTooltipXPosition(
    Offset globalPosition,
    Size tooltipSize,
    Size screenSize,
  ) {
    var xPosition =
        widget.padding.left +
        globalPosition.dx -
        tooltipSize.width; // Initial offset to the left
    if (xPosition + tooltipSize.width > screenSize.width) {
      // If tooltip exceeds right boundary
      xPosition =
          globalPosition.dx - tooltipSize.width - 10; // Offset to the right
    } else if (xPosition < tooltipSize.width) {
      // Move to the right if tooltip exceeds left boundary
      xPosition =
          widget.padding.left + globalPosition.dx + 10; // Offset to the left
    } else {
      xPosition -= 10; // Offset to the left
    }
    return xPosition;
  }

  double _calculateTooltipYPosition(
    Offset globalPosition,
    Size tooltipSize,
    Size screenSize,
  ) {
    var yPosition =
        widget.padding.top +
        globalPosition.dy -
        tooltipSize.height; // Initial offset to the top
    if (yPosition + tooltipSize.height > screenSize.height) {
      // If tooltip exceeds bottom boundary
      yPosition =
          globalPosition.dy - tooltipSize.height - 10; // Offset to the bottom
    } else if (yPosition < tooltipSize.height) {
      // Move to the bottom if tooltip exceeds top boundary
      yPosition =
          widget.padding.top + globalPosition.dy + 10; // Offset to the top
    } else {
      yPosition -= 10; // Offset to the top
    }
    return yPosition;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.elements,
    required this.transform,
    required this.highlightedPoints,
    required this.highlightedColors,
    required this.animation,
    required this.markerSelectionStrategy,
    required this.hoverPosition,
  });
  final List<ChartElement> elements;
  final ChartDataTransform transform;
  final List<Offset>? highlightedPoints;
  final List<Color> highlightedColors;
  final double animation;
  final MarkerSelectionStrategy? markerSelectionStrategy;
  final Offset? hoverPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final dataElements = elements.whereType<ChartDataSeries>();
    final nonDataElements = elements.where(
      (element) => element is! ChartDataSeries,
    );

    // Paint non-data elements (e.g., grid lines, axis labels)
    for (final element in nonDataElements) {
      element.paint(canvas, size, transform, animation);
    }

    // Save the canvas state before applying the clip
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        0,
        0,
        size.width,
        size.height,
      ),
    );

    // Paint data elements (e.g., data series) within the clipped area
    for (final element in dataElements) {
      final visibleData = _getVisibleData(element.data);
      element
          .copyWith(data: visibleData)
          .paint(canvas, size, transform, animation);
    }

    // Restore the canvas state to remove the clip
    canvas.restore();

    // Filter highlighted points to only include those within the visible domain
    final filteredHighlightedPoints = _getFilteredHighlightedPoints();

    // Paint markers outside the clipped area
    if (markerSelectionStrategy != null) {
      markerSelectionStrategy!.paint(
        canvas,
        size,
        transform,
        filteredHighlightedPoints,
        highlightedColors,
        hoverPosition,
      );
    }
  }

  List<Offset> _getFilteredHighlightedPoints() {
    if (highlightedPoints == null) return [];

    final minX = transform.minX;
    final maxX = transform.maxX;

    return highlightedPoints!.where((point) {
      final xValue = transform.reverseTransformX(point.dx);
      return xValue >= minX && xValue <= maxX;
    }).toList();
  }

  List<ChartData> _getVisibleData(List<ChartData> data) {
    final visibleData = <ChartData>[];
    ChartData? firstOutOfDomain;
    ChartData? lastOutOfDomain;
    final minX = transform.minX;
    final maxX = transform.maxX;

    for (final dataPoint in data) {
      final xValue = dataPoint.x;
      if (xValue >= minX && xValue <= maxX) {
        visibleData.add(dataPoint);
      } else if (xValue < minX &&
          (firstOutOfDomain == null || xValue > firstOutOfDomain.x)) {
        firstOutOfDomain = dataPoint;
      } else if (xValue > maxX &&
          (lastOutOfDomain == null || xValue < lastOutOfDomain.x)) {
        lastOutOfDomain = dataPoint;
      }
    }

    if (firstOutOfDomain != null) {
      visibleData.insert(0, firstOutOfDomain);
    }

    if (lastOutOfDomain != null) {
      visibleData.add(lastOutOfDomain);
    }

    return visibleData;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.hoverPosition != hoverPosition ||
        !listEquals(oldDelegate.elements, elements) ||
        !listEquals(oldDelegate.highlightedColors, highlightedColors) ||
        oldDelegate.transform != transform ||
        oldDelegate.markerSelectionStrategy != markerSelectionStrategy ||
        !listEquals(oldDelegate.highlightedPoints, highlightedPoints);
  }
}

typedef SizeCallback = void Function(Size size);

class MeasureSize extends StatefulWidget {
  const MeasureSize({
    required this.onSizeChange,
    required this.child,
    super.key,
  });
  final Widget child;
  final SizeCallback onSizeChange;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_postFrameCallback);
    return Container(
      key: widget.key,
      child: widget.child,
    );
  }

  void _postFrameCallback(_) {
    if (!mounted) return;
    final context = this.context;
    final size = context.size;
    if (size != null) {
      widget.onSizeChange(size);
    }
  }
}
