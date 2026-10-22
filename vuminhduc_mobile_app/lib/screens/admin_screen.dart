import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await _authService.getUsers();
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _showAssignRoleDialog(Map<String, dynamic> user) async {
    String currentRole = user['role'] ?? 'Member';
    String selectedRole = currentRole;
    final username = user['username'] ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Phân Quyền: $username', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email: ${user['email'] ?? "Chưa có"}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 16),
                const Text('Chọn vai trò mới trong hệ thống:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: ['Admin', 'Owner', 'Member', 'Child'].contains(selectedRole) ? selectedRole : 'Member',
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  items: const [
                    DropdownMenuItem(value: 'Admin', child: Text('Quản trị viên (Admin)')),
                    DropdownMenuItem(value: 'Owner', child: Text('Chủ gia đình (Family Owner)')),
                    DropdownMenuItem(value: 'Member', child: Text('Thành viên gia đình (Member)')),
                    DropdownMenuItem(value: 'Child', child: Text('Trẻ em (Child)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => selectedRole = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final res = await _authService.assignRole(username, selectedRole);
                if (!mounted) return;
                if (res['success'] == true) {
                  setState(() {
                    final index = _users.indexWhere((u) => u['username'] == username);
                    if (index != -1) {
                      _users[index] = Map<String, dynamic>.from(_users[index]);
                      _users[index]['role'] = selectedRole;
                    }
                  });
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Thành công'),
                    backgroundColor: res['success'] == true ? AppTheme.success : AppTheme.error,
                  ),
                );
              },
              child: const Text('Cập nhật quyền'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.adminGradient),
        ),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'QUẢN TRỊ VIÊN HỆ THỐNG',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadUsers,
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: _users.isEmpty
                  ? const Center(child: Text('Chưa có người dùng nào', style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      itemBuilder: (ctx, i) {
                        final u = _users[i];
                        final role = u['role']?.toString() ?? 'Member';

                        Color roleColor = Colors.lightGreenAccent;
                        String roleLabel = 'Thành viên';
                        IconData roleIcon = Icons.person;

                        if (role == 'Admin') {
                          roleColor = Colors.redAccent;
                          roleLabel = 'Quản trị viên';
                          roleIcon = Icons.admin_panel_settings;
                        } else if (role == 'Owner') {
                          roleColor = Colors.purpleAccent;
                          roleLabel = 'Chủ gia đình';
                          roleIcon = Icons.home;
                        } else if (role == 'Child') {
                          roleColor = Colors.amberAccent;
                          roleLabel = 'Trẻ em';
                          roleIcon = Icons.child_care;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: roleColor.withValues(alpha: 0.2),
                              child: Icon(roleIcon, color: roleColor),
                            ),
                            title: Text(
                              u['username'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['email'] ?? 'Không có email', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                if (u['phoneNumber'] != null)
                                  Text('SĐT: ${u['phoneNumber']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                              ],
                            ),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: roleColor.withValues(alpha: 0.2),
                                foregroundColor: roleColor,
                                side: BorderSide(color: roleColor.withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.edit, size: 14),
                              label: Text(roleLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _showAssignRoleDialog(u),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
