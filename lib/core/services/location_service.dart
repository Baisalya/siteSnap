import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/core/utils/overlay_utils.dart';

class LocationService {
  static Future<String?> getLocationName(double lat, double lng, {AppLanguage? language}) async {
    try {
      if (language != null) {
        final resolved = OverlayUtils.resolveLanguage(language);
        await setLocaleIdentifier(resolved.name);
      }

      List<Placemark> placemarks = await placemarkFromCoordinates(
        lat, 
        lng,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        // We use a Set to avoid duplicate strings (e.g. if name and street are the same)
        final List<String> parts = [];

        void addIfNotEmpty(String? value) {
          if (value != null && value.isNotEmpty && !parts.contains(value)) {
            parts.add(value);
          }
        }

        // 1. Specific Location/Building Name
        addIfNotEmpty(place.name);

        // 2. Street Address
        addIfNotEmpty(place.subThoroughfare); // House/Building number
        addIfNotEmpty(place.thoroughfare);    // Street name

        // 3. Neighborhood/District
        addIfNotEmpty(place.subLocality);     // Neighborhood
        addIfNotEmpty(place.locality);        // City

        // 4. District/County
        addIfNotEmpty(place.subAdministrativeArea); // County/District

        // 5. State/Province
        addIfNotEmpty(place.administrativeArea);

        // 6. Postal Code
        addIfNotEmpty(place.postalCode);

        // 7. Country
        addIfNotEmpty(place.country);

        if (parts.isEmpty) return "Unknown Location";

        return parts.join(", ");
      }
    } catch (e) {
      debugPrint("Error fetching location name: $e");
    }
    return null;
  }
}
