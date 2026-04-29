import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/features/compass/data/compass_repository_impl.dart';

final compassHeadingProvider = StreamProvider<double>((ref) {
  final repo = CompassRepositoryImpl();
  return repo.headingStream;
});
