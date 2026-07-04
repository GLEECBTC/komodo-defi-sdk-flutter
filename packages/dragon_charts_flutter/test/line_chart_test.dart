import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LineChart', () {
    testWidgets('should render LineChart with elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineChart(
              elements: [
                ChartGridLines(isVertical: false, count: 5),
                ChartAxisLabels(
                  isVertical: true,
                  count: 5,
                  labelBuilder: (value) => value.toStringAsFixed(2),
                ),
                ChartAxisLabels(
                  isVertical: false,
                  count: 5,
                  labelBuilder: (value) => value.toStringAsFixed(2),
                ),
                ChartDataSeries(
                  data: [ChartData(x: 1, y: 2)],
                  color: Colors.blue,
                ),
                ChartDataSeries(
                  data: [ChartData(x: 1, y: 4)],
                  color: Colors.red,
                  lineType: LineType.bezier,
                ),
              ],
              // tooltipBuilder: (context, dataPoints) {
              //   return ChartTooltip(
              //     dataPoints: dataPoints,
              //     backgroundColor: Colors.black,
              //   );
              // },
            ),
          ),
        ),
      );

      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets(
      'does not restart the line animation when rebuilt with identical data',
      (WidgetTester tester) async {
        final rebuild = ValueNotifier<int>(0);
        List<ChartElement> buildElements() => [
          ChartDataSeries(
            data: [ChartData(x: 1, y: 2), ChartData(x: 2, y: 3)],
            color: Colors.blue,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: rebuild,
                builder: (_, __, ___) => LineChart(
                  elements: buildElements(),
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        );
        // Settle the initial entry animation.
        await tester.pumpAndSettle();

        // Force a parent rebuild that passes a fresh list with identical data.
        rebuild.value++;
        final framesPumped = await tester.pumpAndSettle();

        // No 500ms re-animation should be triggered, so settling takes ~1 frame.
        expect(framesPumped, lessThan(3));
        addTearDown(rebuild.dispose);
      },
    );

    testWidgets('restarts the line animation when the data changes', (
      WidgetTester tester,
    ) async {
      final rebuild = ValueNotifier<int>(0);
      var y = 2.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (_, __, ___) => LineChart(
                elements: [
                  ChartDataSeries(
                    data: [ChartData(x: 1, y: y)],
                    color: Colors.blue,
                  ),
                ],
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change the plotted value and rebuild.
      y = 9;
      rebuild.value++;
      final framesPumped = await tester.pumpAndSettle();

      // A real data change must animate, pumping multiple frames over 500ms.
      expect(framesPumped, greaterThan(3));
      addTearDown(rebuild.dispose);
    });
  });
}
