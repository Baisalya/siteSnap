import 'package:intl/intl.dart';
import '../../features/overlay/domain/overlay_settings.dart';

class OverlayUtils {
  static String formatCoordinate(double value, bool isLatitude, CoordinateFormat format) {
    if (format == CoordinateFormat.decimal) {
      return value.toStringAsFixed(6);
    } else {
      // DMS Format: 52° 31' 12" N
      final degrees = value.abs().floor();
      final minutesDecimal = (value.abs() - degrees) * 60;
      final minutes = minutesDecimal.floor();
      final seconds = ((minutesDecimal - minutes) * 60).toStringAsFixed(1);
      
      String direction = "";
      if (isLatitude) {
        direction = value >= 0 ? "N" : "S";
      } else {
        direction = value >= 0 ? "E" : "W";
      }
      
      return "$degrees° $minutes' $seconds\" $direction";
    }
  }

  static String getLabel(String key, AppLanguage language) {
    const translations = {
      'latitude': {
        AppLanguage.en: 'Latitude',
        AppLanguage.de: 'Breitengrad',
        AppLanguage.ru: 'Широта',
        AppLanguage.hi: 'अक्षांश',
        AppLanguage.es: 'Latitud',
        AppLanguage.fr: 'Latitude',
        AppLanguage.pt: 'Latitude',
        AppLanguage.it: 'Latitudine',
      },
      'longitude': {
        AppLanguage.en: 'Longitude',
        AppLanguage.de: 'Längengrad',
        AppLanguage.ru: 'Долгота',
        AppLanguage.hi: 'देशांतर',
        AppLanguage.es: 'Longitud',
        AppLanguage.fr: 'Longitude',
        AppLanguage.pt: 'Longitude',
        AppLanguage.it: 'Longitudine',
      },
      'altitude': {
        AppLanguage.en: 'ALT',
        AppLanguage.de: 'HÖHE',
        AppLanguage.ru: 'ВЫС',
        AppLanguage.hi: 'ऊंचाई',
        AppLanguage.es: 'ALT',
        AppLanguage.fr: 'ALT',
        AppLanguage.pt: 'ALT',
        AppLanguage.it: 'ALT',
      },
      'direction': {
        AppLanguage.en: 'DIR',
        AppLanguage.de: 'RICHT',
        AppLanguage.ru: 'НАПР',
        AppLanguage.hi: 'दिशा',
        AppLanguage.es: 'DIR',
        AppLanguage.fr: 'DIR',
        AppLanguage.pt: 'DIR',
        AppLanguage.it: 'DIR',
      },
      'weather': {
        AppLanguage.en: 'Weather',
        AppLanguage.de: 'Wetter',
        AppLanguage.ru: 'Погода',
        AppLanguage.hi: 'मौसम',
        AppLanguage.es: 'Clima',
        AppLanguage.fr: 'Météo',
        AppLanguage.pt: 'Clima',
        AppLanguage.it: 'Meteo',
      },
      'humidity': {
        AppLanguage.en: 'Humidity',
        AppLanguage.de: 'Feuchtigkeit',
        AppLanguage.ru: 'Влажность',
        AppLanguage.hi: 'नमी',
        AppLanguage.es: 'Humedad',
        AppLanguage.fr: 'Humidité',
        AppLanguage.pt: 'Umidade',
        AppLanguage.it: 'Umidità',
      },
      'pressure': {
        AppLanguage.en: 'Pressure',
        AppLanguage.de: 'Druck',
        AppLanguage.ru: 'Давление',
        AppLanguage.hi: 'दबाव',
        AppLanguage.es: 'Presión',
        AppLanguage.fr: 'Pression',
        AppLanguage.pt: 'Pressão',
        AppLanguage.it: 'Pressione',
      },
      'air': {
        AppLanguage.en: 'Air',
        AppLanguage.de: 'Luft',
        AppLanguage.ru: 'Воздух',
        AppLanguage.hi: 'वायु',
        AppLanguage.es: 'Aire',
        AppLanguage.fr: 'Air',
        AppLanguage.pt: 'Ar',
        AppLanguage.it: 'Aria',
      },
    };

    return translations[key]?[language] ?? translations[key]?[AppLanguage.en] ?? key;
  }

  static String formatDateTime(DateTime dateTime, AppLanguage language, bool use24Hour) {
    String pattern = "dd/MM/yyyy HH:mm:ss";
    
    if (language == AppLanguage.de || language == AppLanguage.ru || language == AppLanguage.it) {
      pattern = "dd.MM.yyyy ${use24Hour ? 'HH:mm:ss' : 'hh:mm:ss a'}";
    } else if (language == AppLanguage.fr) {
      pattern = "dd/MM/yyyy ${use24Hour ? 'HH:mm:ss' : 'hh:mm:ss a'}";
    } else {
      pattern = "dd/MM/yyyy ${use24Hour ? 'HH:mm:ss' : 'hh:mm:ss a'}";
    }
    
    return DateFormat(pattern).format(dateTime);
  }
}
