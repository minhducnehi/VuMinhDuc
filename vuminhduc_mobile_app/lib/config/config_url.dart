import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigUrl {
  static String? _customBaseUrl;

  /// Khởi tạo và đọc baseUrl đã lưu nếu có
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_base_url');
      // Nếu lưu nhầm relative path "/api/" trong môi trường dev trên web, reset để tránh lỗi kết nối
      if (saved == '/api/' || saved == '/api') {
        await prefs.remove('custom_base_url');
        _customBaseUrl = null;
      } else {
        _customBaseUrl = saved;
      }
    } catch (_) {}
  }

  /// Cập nhật URL mới và lưu vào máy
  static Future<void> setCustomBaseUrl(String newUrl) async {
    var formatted = newUrl.trim();
    if (!formatted.endsWith('/')) {
      formatted += '/';
    }
    _customBaseUrl = formatted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_base_url', formatted);
  }

  /// Khôi phục URL mặc định từ .env
  static Future<void> resetToDefault() async {
    _customBaseUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_base_url');
  }

  /// Lấy baseUrl hiện tại
  static String get baseUrl {
    if (_customBaseUrl != null &&
        _customBaseUrl!.isNotEmpty &&
        _customBaseUrl != '/api/' &&
        _customBaseUrl != '/api') {
      return _customBaseUrl!;
    }

    // Đọc URL từ file .env nếu có
    String? envUrl;
    try {
      if (dotenv.isInitialized) {
        final url = dotenv.env['BASE_URL'];
        if (url != null && url.isNotEmpty) {
          envUrl = url.endsWith('/') ? url : '$url/';
        }
      }
    } catch (_) {}

    // Trên Web:
    if (kIsWeb) {
      // Khi chạy 'flutter run -d chrome': app chạy trên web server debug nội bộ của Flutter (cổng ngẫu nhiên 5xxxx)
      // Trong khi Backend ASP.NET Core chạy ở cổng 5000 hoặc 8687.
      // Dùng relative path '/api/' sẽ gọi vào server Flutter -> Gây lỗi kết nối (404/Failed to fetch).
      // Do đó: nếu đang ở chế độ Debug HOẶC cổng hiện tại khác cổng backend (5000, 5102, 8687, 80, 443),
      // BẮT BUỘC dùng URL tuyệt đối trỏ tới Backend (ưu tiên .env, mặc định http://localhost:5000/api/).
      final port = Uri.base.port;
      final isFlutterDevServer = kDebugMode ||
          (port != 5000 && port != 5102 && port != 8687 && port != 80 && port != 443);

      if (isFlutterDevServer) {
        return envUrl ?? "http://localhost:5000/api/";
      }

      // Khi đã build deploy chung vào wwwroot của backend (truy cập cùng origin:port):
      return "/api/";
    }

    return envUrl ?? "http://localhost:5000/api/";
  }
}
