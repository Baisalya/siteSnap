import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/presentation/camera_zoom_hud.dart';

void main() {
  testWidgets('zoom HUD exposes animated ratio feedback and reset action',
      (tester) async {
    var resetCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CameraZoomHud(
              zoom: 2.4,
              minZoom: 1,
              maxZoom: 8,
              isGestureActive: true,
              onReset: () => resetCount++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2.4x'), findsOneWidget);
    expect(find.byType(AnimatedScale), findsWidgets);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(Align), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.tap(find.text('2.4x'));
    await tester.pump();
    expect(resetCount, 1);
  });

  testWidgets('zoom HUD stays valid at a single supported zoom ratio',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraZoomHud(
            zoom: 1,
            minZoom: 1,
            maxZoom: 1,
            isGestureActive: false,
            onReset: () {},
          ),
        ),
      ),
    );

    expect(find.text('1.0x'), findsOneWidget);
  });
}
