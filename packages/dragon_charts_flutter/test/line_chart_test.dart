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
  });
}
