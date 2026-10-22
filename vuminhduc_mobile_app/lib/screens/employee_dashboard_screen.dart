import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import 'login_screen.dart';

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() => _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DataService _dataService = DataService();

  String _username = 'Nhân viên';
  List<ProductPost> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? 'Nhân viên';

    try {
      final prods = await _dataService.getProducts();
      final cats = await _dataService.getCategories();
      setState(() {
        _products = prods;
        _categories = cats;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0284C7), Color(0xFF0369A1)], // Ocean Blue
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Icon(Icons.badge_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dashboard Nhân Viên: $_username', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('Quyền hạn: Employee (Quản lý đơn hàng & Kho)', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: const Text('Đăng xuất'),
                  content: const Text('Xác nhận đăng xuất khỏi ca làm việc?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleLogout();
                      },
                      child: const Text('Đăng xuất'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Tổng Quan & Thống Kê'),
            Tab(icon: Icon(Icons.inventory_outlined), text: 'Kiểm Kê Kho Hàng'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: TỔNG QUAN NHÂN VIÊN
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thẻ chào mừng ca làm việc
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.work_history_outlined, color: Colors.lightBlueAccent, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Xin chào, $_username!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                        const Text('Ca làm việc đang hoạt động • Trạng thái: Sẵn sàng', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Metrics Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard('Sản phẩm trong kho', '${_products.length}', Icons.inventory, Colors.tealAccent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard('Danh mục quản lý', '${_categories.length}', Icons.category, Colors.amberAccent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Hoạt động nhiệm vụ nhân viên
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Nhiệm vụ trong ngày của nhân viên:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 12),
                              _buildTaskItem('Kiểm tra hạn sử dụng các mặt hàng trên kệ', true),
                              _buildTaskItem('Cập nhật số lượng tồn kho theo ca', true),
                              _buildTaskItem('Xử lý các bài phản hồi của khách hàng trên Feed', false),
                              _buildTaskItem('Báo cáo doanh số bán hàng cuối ca cho Admin', false),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // TAB 2: KIỂM KÊ KHO HÀNG
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (ctx, i) {
                    final p = _products[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey,
                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(
                          'Giá niêm yết: ${p.price.toStringAsFixed(0)} ₫ • ${p.category?.name ?? "Chưa phân loại"}',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã ghi nhận kiểm kê cho sản phẩm: ${p.name}')),
                            );
                          },
                          child: const Text('Đã kiểm', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(String title, bool isDone) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? Colors.greenAccent : Colors.grey, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: isDone ? Colors.white70 : Colors.white,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
