import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/config_url.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'family_safety_screen.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _stepOtp = false; // true: đang ở màn hình nhập mã OTP
  String _userEmailForOtp = '';
  String _currentBaseUrl = ConfigUrl.baseUrl;
  Timer? _errorTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Hiển thị thông báo lỗi (sai mật khẩu, sai OTP...) đúng 5 giây rồi tự động biến mất hoàn toàn
  void _showErrorMessage(String message) {
    _errorTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );

    // Đếm ngược đúng 5 giây để ẩn SnackBar và xóa banner lỗi trên form
    _errorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  // Tự động kiểm tra token lưu trong máy khi mở app (Yêu cầu 5)
  Future<void> _checkSavedSession() async {
    final token = await AuthService.getSavedToken();
    if (token != null && mounted) {
      final role = await AuthService.getSavedRole();
      final username = await AuthService.getSavedUsername();
      _navigateByRole(role, username);
    }
  }

  // 3. Phân quyền người dùng điều hướng chuẩn xác:
  // - Admin: vào trang quản trị (AdminScreen)
  // - Employee: vào Dashboard nhân viên (EmployeeDashboardScreen)
  // - Customer: vào trang mua sắm & bảng tin (MainScreen)
  void _navigateByRole(String role, [String? savedUsername]) {
    if (!mounted) return;
    final normalized = role.toLowerCase().trim();
    String username = _usernameController.text.trim();
    if (username.isEmpty && savedUsername != null && savedUsername.isNotEmpty) {
      username = savedUsername;
    }
    if (username.isEmpty) {
      username = 'duc';
    }

    if (normalized == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      );
    } else {
      // 3 vai trò gia đình: Chủ gia đình (Owner), Thành viên gia đình (Member), Trẻ em (Child)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FamilySafetyScreen(
            role: role,
            username: username,
          ),
        ),
      );
    }
  }

  // BƯỚC 1: Xác thực Username + Mật khẩu -> Đòi OTP
  Future<void> _handleRequestOtp() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showErrorMessage('Vui lòng nhập đầy đủ Tên đăng nhập và Mật khẩu!');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _errorTimer?.cancel();

    final result = await _authService.requestLoginOtp(username, password);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _stepOtp = true;
        _userEmailForOtp = result['email'] ?? '';
        _otpController.clear(); // Để trống để người dùng nhập OTP từ Gmail thực tế
      });

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.mark_email_read, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Đã gửi mã OTP đến ${_userEmailForOtp.isNotEmpty ? _userEmailForOtp : "email"}!'),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      final msg = result['message'] ?? 'Tài khoản hoặc mật khẩu không chính xác!';
      _showErrorMessage(msg);
    }
  }

  // BƯỚC 2: Xác thực mã OTP -> Cấp JWT Token & Phân quyền Role
  Future<void> _handleVerifyOtp() async {
    final username = _usernameController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      _showErrorMessage('Vui lòng nhập mã OTP 6 chữ số!');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _errorTimer?.cancel();

    final result = await _authService.verifyLoginOtp(username, otp);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      final role = result['role'] as String;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.verified_user, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Xác thực thành công! Vai trò: $role')),
            ],
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ),
      );
      _navigateByRole(role);
    } else {
      _showErrorMessage(result['message'] ?? 'Mã OTP không hợp lệ!');
    }
  }

  void _showConfigUrlDialog() {
    final urlController = TextEditingController(text: ConfigUrl.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.settings_ethernet, color: AppTheme.secondary),
            SizedBox(width: 8),
            Text('Cấu hình API Endpoint', style: TextStyle(fontSize: 18, color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn nhanh hoặc nhập URL của Backend:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildQuickChip('Localhost 5000', 'http://localhost:5000/api/', urlController),
                _buildQuickChip('Docker 8687', 'http://localhost:8687/api/', urlController),
                _buildQuickChip('Android Emulator', 'http://10.0.2.2:5000/api/', urlController),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ConfigUrl.resetToDefault();
              setState(() => _currentBaseUrl = ConfigUrl.baseUrl);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Mặc định', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                await ConfigUrl.setCustomBaseUrl(newUrl);
                setState(() => _currentBaseUrl = ConfigUrl.baseUrl);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String url, TextEditingController controller) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: AppTheme.surfaceElevated,
      onPressed: () {
        controller.text = url;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEEF2FF), Color(0xFFE0F2FE), Color(0xFFF8FAFC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Header / Logo
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.family_restroom, size: 44, color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'VŨ MINH ĐỨC - FAMILY SAFETY',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'HỆ THỐNG AN TOÀN & QUẢN LÝ GIA ĐÌNH THÔNG MINH',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Main Card (Đổi giữa Bước 1 và Bước 2 OTP)
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _stepOtp ? _buildOtpVerificationUI() : _buildLoginFormUI(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Navigation to Register
                    if (!_stepOtp)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Chưa có tài khoản? ', style: TextStyle(color: AppTheme.textSecondary)),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegistrationScreen()),
                              );
                            },
                            child: const Text('Đăng ký qua Email', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),

                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.tune, size: 16, color: AppTheme.textSecondary),
                      label: Text(
                        'API: $_currentBaseUrl',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _showConfigUrlDialog,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Giao diện Bước 1: Nhập Tên đăng nhập + Mật khẩu
  Widget _buildLoginFormUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Đăng Nhập Tài Khoản',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Bước 1: Nhập tài khoản & mật khẩu',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _usernameController,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập',
            hintText: 'Nhập tên đăng nhập',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          decoration: InputDecoration(
            labelText: 'Mật khẩu',
            hintText: '••••••••',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _isLoading ? null : _handleRequestOtp,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forward_to_inbox, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'TIẾP TỤC & GỬI MÃ OTP',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // Giao diện Bước 2: Nhập mã xác thực OTP
  Widget _buildOtpVerificationUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _stepOtp = false),
            ),
            const Expanded(
              child: Text(
                'Xác Thực Mã OTP',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Column(
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: AppTheme.primary, size: 36),
              const SizedBox(height: 8),
              Text(
                'Mã OTP 6 số đã được gửi đến email:\n$_userEmailForOtp',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.bold, color: AppTheme.primary),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          decoration: const InputDecoration(
            labelText: 'Mã xác thực OTP (6 chữ số)',
            hintText: '123456',
            prefixIcon: Icon(Icons.pin),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _isLoading ? null : _handleVerifyOtp,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'XÁC NHẬN & ĐĂNG NHẬP',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading ? null : _handleRequestOtp,
          child: const Text('Chưa nhận được mã? Gửi lại OTP', style: TextStyle(color: AppTheme.secondary, fontSize: 13)),
        ),
      ],
    );
  }
}
