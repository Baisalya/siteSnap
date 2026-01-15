import 'package:intl/intl.dart';

class DateTimeUtils {
  static String formattedNow() {
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
  }
}
