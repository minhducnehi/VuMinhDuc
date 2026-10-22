import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/config_url.dart';

class VietmapService {
  // Key chính thức do người dùng cung cấp
  static const String defaultServicesKey = '074a83210e880458e187c0b14479376f061fed1174db5a44';
  static const String defaultTilemapKey = '22e06c2e525539b85e2d5f8a37105a85817a6bfdf3889b41';

  static String? _customApiKey;
  static final Map<String, Uint8List> _imageCache = {};
  static final Map<String, String> _addressCache = {};

  static void _saveToImageCache(String key, Uint8List bytes) {
    if (_imageCache.length >= 40) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[key] = bytes;
  }

  /// Khởi tạo và đọc API key từ bộ nhớ cục bộ
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customApiKey = prefs.getString('vietmap_api_key');
    } catch (_) {}
  }

  /// Lấy API key bản đồ hiện tại (Ưu tiên: Custom Key > .env > defaultServicesKey)
  static String get apiKey {
    if (_customApiKey != null && _customApiKey!.trim().isNotEmpty) {
      return _customApiKey!.trim();
    }
    try {
      if (dotenv.isInitialized) {
        final envKey = dotenv.env['VIETMAP_SERVICES_KEY'] ?? dotenv.env['VIETMAP_API_KEY'];
        if (envKey != null && envKey.trim().isNotEmpty) {
          return envKey.trim();
        }
      }
    } catch (_) {}
    return defaultServicesKey;
  }

  /// Lấy Tilemap Key (dùng cho tải tile/style)
  static String get tilemapKey {
    try {
      if (dotenv.isInitialized) {
        final envKey = dotenv.env['VIETMAP_TILEMAP_KEY'];
        if (envKey != null && envKey.trim().isNotEmpty) {
          return envKey.trim();
        }
      }
    } catch (_) {}
    return defaultTilemapKey;
  }

  /// Cập nhật custom API key (lưu vào SharedPreferences)
  static Future<void> setCustomApiKey(String key) async {
    _customApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vietmap_api_key', _customApiKey!);
    _imageCache.clear();
  }

  /// Khôi phục API key mặc định
  static Future<void> resetApiKey() async {
    _customApiKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vietmap_api_key');
    _imageCache.clear();
  }

  /// Lấy URL ảnh tĩnh proxy từ server backend (triệt tiêu 100% lỗi CORS trên Web)
  static String getStaticMapUrl({
    required double lat,
    required double lng,
    int zoom = 16,
    int width = 600,
    int height = 360,
    String? address,
  }) {
    final base = ConfigUrl.baseUrl.endsWith('/') ? ConfigUrl.baseUrl : '${ConfigUrl.baseUrl}/';
    final addrParam = address != null && address.trim().isNotEmpty ? '&address=${Uri.encodeComponent(address)}' : '';
    return '${base}FamilySafety/vietmap-static?lat=$lat&lng=$lng&zoom=$zoom&width=$width&height=$height$addrParam';
  }

  /// Lấy ảnh bản đồ PNG từ Backend Proxy hoặc trực tiếp VietMap
  static Future<Uint8List?> fetchStaticMapBytes({
    required double lat,
    required double lng,
    int zoom = 16,
    int width = 600,
    int height = 360,
    String? address,
  }) async {
    final cacheKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}_${zoom}_${width}x$height';
    if (_imageCache.containsKey(cacheKey)) {
      return _imageCache[cacheKey];
    }

    // 1. Thử tải qua Backend Proxy (Không bao giờ bị lỗi CORS trên Web & App)
    try {
      final proxyUrl = getStaticMapUrl(
        lat: lat,
        lng: lng,
        zoom: zoom,
        width: width,
        height: height,
        address: address,
      );
      final resp = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        _saveToImageCache(cacheKey, resp.bodyBytes);
        return resp.bodyBytes;
      }
    } catch (e) {
      debugPrint('[VietmapService] Proxy map fetch error: $e');
    }

    // 2. Thử gọi trực tiếp VietMap qua GET Request
    final keysToTry = [apiKey, tilemapKey];
    for (final key in keysToTry) {
      try {
        final directUri = Uri.parse(
          'https://maps.vietmap.vn/api/maps/statics/tm?apikey=$key&lat=$lat&lng=$lng&zoom=$zoom&size=${width}x$height',
        );
        final resp = await http.get(directUri).timeout(const Duration(seconds: 7));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          _imageCache[cacheKey] = resp.bodyBytes;
          return resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[VietmapService] Direct Vietmap GET error: $e');
      }
    }

    // 3. Dự phòng: ảnh OpenStreetMap tĩnh
    try {
      final fallbackUrl = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=$zoom&size=${width}x$height&maptype=mapnik&markers=$lat,$lng,ol-marker',
      );
      final resp = await http.get(fallbackUrl).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        _saveToImageCache(cacheKey, resp.bodyBytes);
        return resp.bodyBytes;
      }
    } catch (fallbackErr) {
      debugPrint('[VietmapService] Fallback map error: $fallbackErr');
    }

    return null;
  }

  /// Tra cứu địa chỉ thời gian thực từ tọa độ GPS qua VietMap Reverse Geocoding v4
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';
    if (_addressCache.containsKey(cacheKey)) {
      return _addressCache[cacheKey];
    }

    try {
      final url = Uri.parse('https://maps.vietmap.vn/api/reverse/v4?apikey=$apiKey&lat=$lat&lng=$lng');
      final response = await http.get(url).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List && decoded.isNotEmpty) {
          final item = decoded[0];
          final display = item['display'] as String?;
          final name = item['name'] as String?;
          final addr = item['address'] as String?;

          String result = '';
          if (display != null && display.isNotEmpty) {
            result = display;
          } else if (name != null && addr != null) {
            result = '$name, $addr';
          } else {
            result = addr ?? name ?? '';
          }

          if (result.isNotEmpty) {
            _addressCache[cacheKey] = result;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('[VietmapService] reverseGeocode error: $e');
    }

    return null;
  }

  /// Mở ứng dụng Bản đồ ngoài để phụ huynh dẫn đường trực tiếp đến con
  static Future<bool> openDirectionsToChild(double lat, double lng, {String? childName}) async {
    // 1. Google Maps Navigation URL
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    // 2. Vietmap Live Web
    final vietmapWebUrl = Uri.parse('https://maps.vietmap.vn/?lat=$lat&lng=$lng&zoom=16');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        return await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    try {
      return await launchUrl(vietmapWebUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Mở liên kết trực tiếp trên Vietmap Live Web
  static Future<bool> openVietmapWeb(double lat, double lng) async {
    final uri = Uri.parse('https://maps.vietmap.vn/?lat=$lat&lng=$lng&zoom=16');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
