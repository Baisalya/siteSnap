import 'package:flutter_compass/flutter_compass.dart';
import '../domain/compass_repository.dart';

class CompassRepositoryImpl implements CompassRepository {
  @override
  Stream<double> get headingStream =>
      FlutterCompass.events!
          .where((e) => e.heading != null)
          .map((e) => e.heading!);
}
