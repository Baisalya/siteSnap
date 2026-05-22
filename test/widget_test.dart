import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SurveyCam app builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: SurveyCamApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
