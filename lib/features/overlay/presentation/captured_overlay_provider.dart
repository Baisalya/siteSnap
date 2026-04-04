import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/overlay_model.dart';

final capturedOverlayProvider =
StateProvider<OverlayData?>((ref) => null);