import 'dart:convert';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _api = ApiClient();

  static String extractRole(Map<String, dynamic> decoded) {
    const roleSchema = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role";
    var r = decoded['role'] ?? decoded[roleSchema];
    if (r is List && r.isNotEmpty) return r.first.toString();
    if (r != null) return r.toString();
    return 'Customer';
  }

  /// Bước 1 Đăng nhập: Gửi Username + Mật khẩu -> Server xác thực và gửi mã OTP
  Future<Map<String, dynamic>> requestLoginOtp(String username, String password) async {
    try {
      final res = await _api.post('Authenticate/login-request-otp', body: {
        'username': username,
        'password': password,
      });

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == true) {
        return {
          'success': true,
          'requireOtp': true,
          'message': data['message'] ?? 'Mã OTP đã được gửi',
          'email': data['email'] ?? '',
          'demoOtp': data['demoOtp'] ?? '',
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Tài khoản hoặc mật khẩu không chính xác',
      };
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối máy chủ: $e'};
    }
  }

  /// Bước 2 Đăng nhập: Gửi Username + Mã OTP -> Nhận JWT Token và Role
  Future<Map<String, dynamic>> verifyLoginOtp(String username, String otpCode) async {
    try {
      final res = await _api.post('Authenticate/login-verify-otp', body: {
        'username': username,
        'otpCode': otpCode,
      });

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == true) {
        final token = data['token'] as String;
        final decoded = JwtDecoder.decode(token);
        final role = extractRole(decoded);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('user_role', role);
        await prefs.setString('username', username);

        return {
          'success': true,
          'token': token,
          'role': role,
          'message': data['message'] ?? 'Xác thực OTP thành công!',
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Mã OTP không hợp lệ hoặc đã hết hạn',
      };
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối máy chủ: $e'};
    }
  }

  /// 1. Đăng ký tài khoản qua Email
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
    String? initials,
    String? phoneNumber,
  }) async {
    try {
      final res = await _api.post('Authenticate/register', body: {
        'username': username,
        'email': email,
        'password': password,
        'role': role,
        'initials': initials,
        'phoneNumber': phoneNumber,
      });

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == true) {
        return {'success': true, 'message': data['message'] ?? 'Đăng ký tài khoản thành công!'};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Đăng ký thất bại (${res.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối máy chủ: $e'};
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('username');
  }

  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && !JwtDecoder.isExpired(token)) {
      return token;
    }
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    return null;
  }

  static Future<String> getSavedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await getSavedToken();
    if (token != null) {
      final role = prefs.getString('user_role');
      if (role != null) return role;
      final decoded = JwtDecoder.decode(token);
      return extractRole(decoded);
    }
    return 'Guest';
  }

  static Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  /// Lấy danh sách toàn bộ người dùng (Dành cho Admin)
  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final res = await _api.get('Authenticate/users');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Admin phân quyền cho người dùng
  Future<Map<String, dynamic>> assignRole(String username, String newRole) async {
    try {
      final res = await _api.post('Authenticate/assign-role', body: {
        'username': username,
        'newRole': newRole,
      });
      final data = jsonDecode(res.body);
      return {
        'success': res.statusCode == 200 && data['status'] == true,
        'message': data['message'] ?? 'Phân quyền hoàn tất',
      };
    } catch (e) {
      return {'success': false, 'message': 'Lỗi: $e'};
    }
  }
}
