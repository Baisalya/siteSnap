import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final lastImageProvider = StateProvider<File?>((ref) => null);
