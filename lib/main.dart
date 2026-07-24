import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:surveycam/core/services/foreground_task_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the UI-isolate communication port before any task listener or
  // foreground service can be created.
  FlutterForegroundTask.initCommunicationPort();
  ForegroundTaskConfig.initialize();

  await initializeDateFormatting();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    const ProviderScope(
      child: WithForegroundTask(
        child: SurveyCamApp(),
      ),
    ),
  );
}
