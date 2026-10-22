import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/config_url.dart';
import '../services/auth_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _initialsController = TextEditingController();

  final AuthService _authService = AuthService();

  String _selectedRole = 'Owner'; // Mặc định: "Owner" (Chủ gia đình) hoặc "Member" (Thành viên)
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final initials = _initialsController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() => _isLoading = true);

    final result = await _authService.register(
      username: username,
      email: email,
      password: password,
      role: _selectedRole, // "Owner" hoặc "Member" theo lựa chọn
      initials: initials.isNotEmpty ? initials : (username.length > 2 ? username.substring(0, 2).toUpperCase() : username.toUpperCase()),
      phoneNumber: phone.isNotEmpty ? phone : null,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng ký tài khoản "$username" (${_selectedRole == "Owner" ? "Chủ gia đình" : "Thành viên gia đình"}) thành công! Vui lòng đăng nhập.'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result['message'] ?? 'Đăng ký thất bại!', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Server URL: ${ConfigUrl.baseUrl}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng Ký Tài Khoản Qua Email'),
        backgroundColor: Colors.transparent,
      ),
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
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.primaryLight,
                                child: Icon(Icons.mark_email_read_outlined, color: Colors.white),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tạo Tài Khoản Mới',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    Text(
                                      'Xác thực qua Email & Phân loại quyền hạn',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32, color: AppTheme.surfaceElevated),

                          // Chọn vai trò khi đăng ký: Chủ gia đình hoặc Thành viên trong gia đình
                          const Text(
                            'Chọn vai trò của bạn trong gia đình: *',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // Lựa chọn 1: Chủ gia đình (Owner)
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() => _selectedRole = 'Owner'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == 'Owner' ? const Color(0xFFFAF5FF) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _selectedRole == 'Owner' ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0),
                                        width: _selectedRole == 'Owner' ? 2.2 : 1.2,
                                      ),
                                      boxShadow: _selectedRole == 'Owner'
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _selectedRole == 'Owner' ? const Color(0xFFEDE9FE) : const Color(0xFFF1F5F9),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.admin_panel_settings,
                                            color: _selectedRole == 'Owner' ? const Color(0xFF7C3AED) : Colors.grey,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Chủ gia đình',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: _selectedRole == 'Owner' ? const Color(0xFF6B21A8) : AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Quản lý & Phân quyền',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _selectedRole == 'Owner' ? const Color(0xFF7E22CE) : AppTheme.textSecondary,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (_selectedRole == 'Owner') ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8B5CF6),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text('ĐÃ CHỌN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Lựa chọn 2: Thành viên trong gia đình (Member)
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() => _selectedRole = 'Member'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == 'Member' ? const Color(0xFFF0FDF4) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _selectedRole == 'Member' ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
                                        width: _selectedRole == 'Member' ? 2.2 : 1.2,
                                      ),
                                      boxShadow: _selectedRole == 'Member'
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _selectedRole == 'Member' ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.family_restroom,
                                            color: _selectedRole == 'Member' ? const Color(0xFF16A34A) : Colors.grey,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Thành viên',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: _selectedRole == 'Member' ? const Color(0xFF166534) : AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Tham gia gia đình',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _selectedRole == 'Member' ? const Color(0xFF15803D) : AppTheme.textSecondary,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (_selectedRole == 'Member') ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF16A34A),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text('ĐÃ CHỌN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Tên đăng nhập *',
                              prefixIcon: Icon(Icons.account_circle_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên đăng nhập' : null,
                          ),
                          const SizedBox(height: 16),

                          // 1. Đăng ký qua Email (Yêu cầu 1)
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Địa chỉ Email *',
                              hintText: 'vidu@gmail.com',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Vui lòng nhập Email để nhận mã OTP';
                              if (!v.contains('@') || !v.contains('.')) return 'Email không đúng định dạng';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Số điện thoại liên hệ (Tùy chọn)',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu (Tối thiểu 6 ký tự) *',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppTheme.textSecondary),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                              if (v.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirm,
                            decoration: InputDecoration(
                              labelText: 'Xác nhận lại mật khẩu *',
                              prefixIcon: const Icon(Icons.lock_reset),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: AppTheme.textSecondary),
                                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                            validator: (v) {
                              if (v != _passwordController.text) return 'Mật khẩu xác nhận không khớp!';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check),
                                      SizedBox(width: 8),
                                      Text('HOÀN TẤT ĐĂNG KÝ'),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
