// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/family_safety_service.dart';
import '../services/noise_meter_service.dart';
import '../services/yamnet_audio_safety_service.dart';
import '../services/vietmap_service.dart';
import '../widgets/vietmap_fullscreen_dialog.dart';
import '../widgets/vietmap_viewer_widget.dart';
import 'login_screen.dart';

class FamilySafetyScreen extends StatefulWidget {
  final String role; // "Owner", "Member", "Child", "Admin"
  final String username;

  const FamilySafetyScreen({
    super.key,
    required this.role,
    required this.username,
  });

  @override
  State<FamilySafetyScreen> createState() => _FamilySafetyScreenState();
}

class _FamilySafetyScreenState extends State<FamilySafetyScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final FamilySafetyService _service = FamilySafetyService();

  Map<String, dynamic> _group = {};
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _childRequests = [];
  List<Map<String, dynamic>> _appRules = [];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _members = [];

  bool _isChildDeviceLocked = false; // Trạng thái khóa máy từ xa trên thiết bị con
  bool _isTestLockActive = false; // Chế độ Ba Mẹ thử nghiệm màn hình khóa của con
  String _childLockReason = ''; // Lý do khóa máy từ phụ huynh
  bool _isLoading = true;

  // 1. CHIA SẺ VỊ TRÍ TỰ ĐỘNG LIÊN TỤC 24/7 (CONTINUOUS REAL-TIME GPS STREAM)
  bool _isGettingLocation = false;
  double _currentLat = 10.846939;
  double _currentLng = 106.775958;
  String _currentGpsText = '10.846939, 106.775958 (Đang xác định)';
  String _currentAddressText = 'Khu Công Nghệ Cao, TP. Thủ Đức, TP. Hồ Chí Minh';
  Timer? _childAutoLocationTimer; // Tự động phát GPS liên tục trên máy con
  Timer? _parentAutoRefreshTimer; // Tự động làm mới vị trí con liên tục trên máy Ba Mẹ
  Timer? _childLockPollTimer; // Polling kiểm tra trạng thái khóa máy tức thì trên máy con

  // 2. CẢM BIẾN ĐO TIẾNG ỒN CHẠY SUỐT 24/7 (ĐÃ LỌC NHIỄU & QUY ĐỊNH NGƯỠNG CHUẨN THỰC TẾ)
  double _currentDecibel = 42.0;
  YamnetDetectionResult _lastYamnetResult = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.safeNormal);
  Timer? _noiseTimer;
  bool _isRealMicActive = false;
  final double _noiseThreshold = 82.0; // Ngưỡng kích hoạt cảnh báo mặc định: 82 dB (Tránh báo ảo khi nói chuyện bình thường)
  final double _noiseSensitivity = 1.0; // Hệ số chuẩn thực tế 1.0x
    int _consecutiveNoiseTicks = 0; // Bộ lọc xung: đếm chu kỳ 100ms vượt ngưỡng liên tiếp
  bool _isNoiseDialogShowing = false; // Ngăn chặn dialog bị đè / spam

  // 3. THEO DÕI THỜI GIAN SỬ DỤNG MÁY THỰC TẾ (REAL-TIME SCREEN TIME & LIMITS)
  int _todayUsedSeconds = 0; // Số giây máy đã sử dụng hôm nay (tích lũy thời gian thực)
  int _todayBaseLimitMinutes = 120; // Giới hạn cơ bản mặc định mỗi ngày (phút)
  int _approvedExtraMinutes = 0; // Số phút được Ba Mẹ phê duyệt cấp thêm
  bool _isScreenTimeOverLimit = false; // Cảnh báo vượt ngưỡng thời gian
  Timer? _screenTimeTrackerTimer; // Timer đếm giây chạy ngầm theo thời gian thực
  Timer? _screenTimeServerSyncTimer; // Timer gửi báo cáo định kỳ lên Server
  List<double> _audioWaveform = List.filled(14, 25.0);
  DateTime? _lastNoiseAlertTime;
  final List<Map<String, dynamic>> _noiseIncidents = [
    {
      'db': '86.5',
      'type': 'Phát hiện âm thanh la hét / Va chạm bất thường',
      'time': '15 phút trước',
      'status': 'Đã gửi cảnh báo khẩn cấp đến Ba Mẹ',
    }
  ];

  // 3. BẢO VỆ LƯỚT WEB & CHẶN TỰ ĐỘNG (SAFE WEB & DOWNLOAD SHIELD)
  final List<Map<String, dynamic>> _childWebHistory = [
    {
      'url': 'hocmai.vn',
      'title': 'Học Mãi - Học Trực Tuyến An Toàn',
      'isBlocked': false,
      'time': '10 phút trước',
    },
    {
      'url': 'scratch.mit.edu',
      'title': 'Scratch - Lập Trình Sáng Tạo',
      'isBlocked': false,
      'time': '35 phút trước',
    },
    {
      'url': 'cobac-online.xyz',
      'title': 'Trang cá cược cờ bạc trái phép',
      'isBlocked': true,
      'time': 'Hôm qua (Hệ thống đã chặn)',
    },
  ];

  // AI Assistant Chat state
  final TextEditingController _aiChatCtrl = TextEditingController();
  final TextEditingController _childManualInviteCtrl = TextEditingController();
  final List<Map<String, String>> _aiChatMessages = [];
  bool _isAiReplying = false;

  // Phân quyền rõ ràng theo yêu cầu:
  // - Chủ gia đình (Owner / Admin): Quản lý vị trí tất cả thành viên, giám sát cảnh báo link lạ, CRUD thiết bị/app/lịch
  // - Tất cả thành viên (Owner, Member, Child) khi tham gia nhóm gia đình đều xem được danh sách thành viên!
  bool get isOwner =>
      widget.role.toLowerCase() == 'owner' ||
      widget.role.toLowerCase() == 'admin' ||
      widget.username.toLowerCase() == (_group['ownerId']?.toString().toLowerCase() ?? 'duc');
  bool get isChildOrMember => !isOwner;
  bool get isChild => !isOwner;
  bool get isMember => !isOwner && widget.role.toLowerCase() == 'member';

  @override
  void initState() {
    super.initState();
    // Chủ gia đình: 6 tabs (Vị trí, Khóa máy riêng, Web lạ, App, Lịch trình, QR) | Trẻ em: 5 tabs
    _tabController = TabController(length: isOwner ? 6 : 5, vsync: this);
    _loadAllData();
    // Bật cảm biến đo tiếng ồn chạy suốt 24/7 theo yêu cầu (chỉ kích hoạt trên thiết bị con được bảo vệ)
    if (isChildOrMember) {
      _startContinuousNoiseMonitoring();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndPromptSupervisionConsent();
      });
    }
    // Bật đồng bộ vị trí tự động liên tục 24/7 (Cha mẹ thấy liên tục, con không cần bấm gửi)
    _startContinuousLocationTracking();
    _initScreenTimeTracking();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _noiseTimer?.cancel();
    NoiseMeterService.instance.stopListening();
    _childAutoLocationTimer?.cancel();
    _parentAutoRefreshTimer?.cancel();
    _childLockPollTimer?.cancel();
    _screenTimeTrackerTimer?.cancel();
    _screenTimeServerSyncTimer?.cancel();
    _tabController.dispose();
    _aiChatCtrl.dispose();
    _childManualInviteCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ==============================================================
  // GIÁM SÁT CHẠY NGẦM & CHẶN ỨNG DỤNG CẤM KHI CON THOÁT APP
  // ==============================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!isChild) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      debugPrint('[BACKGROUND_GUARD] Con vừa thoát app / bấm nút Home. Dịch vụ giám sát chạy ngầm 24/7 đang hoạt động.');
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[BACKGROUND_GUARD] Con quay lại ứng dụng. Đồng bộ quy tắc bảo vệ.');
      _loadAllData();
    }
  }

  Future<void> _handleBackgroundProhibitedAppDetected({
    required String appName,
    required String category,
  }) async {
    // 1. Gửi cảnh báo vi phạm về máy Ba Mẹ qua Backend
    await _service.triggerAutoBlock(
      childUsername: widget.username,
      actionType: 'APP_LAUNCH',
      targetName: appName,
      category: category,
    );

    // 2. Kích hoạt khóa cưỡng chế ngay lập tức
    setState(() {
      _isChildDeviceLocked = true;
      _childLockReason = '⛔ HỆ THỐNG CHẠY NGẦM ĐÃ CHẶN: Phát hiện con vừa thoát app và cố gắng mở ứng dụng bị Cha Mẹ cấm: "$appName" ($category).';
    });

    // 3. Đồng bộ trạng thái khóa lên Backend
    await _service.setChildLock(
      childUsername: widget.username,
      isLocked: true,
      reason: 'Phát hiện con thoát app và cố mở ứng dụng bị cấm: "$appName"',
    );

    _loadAllData();
  }

  void _simulateChildOpeningProhibitedApp([String? chosenApp]) {
    final blockedList = _appRules.where((r) => r['isBlocked'] == true).toList();
    final sampleName = chosenApp ?? (blockedList.isNotEmpty ? blockedList.first['appName'] : 'TikTok');
    final sampleCategory = blockedList.isNotEmpty ? (blockedList.first['category'] ?? 'Ứng dụng giải trí') : 'Mạng xã hội ngắn';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFEA580C), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Thử Nghiệm Chạy Ngầm & Chặn App Cấm',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF9A3412)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tình huống giả định:\nCon vừa bấm nút Home để thoát ứng dụng này, sau đó mở một ứng dụng đang bị Ba Mẹ bật chặn.',
              style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, color: Color(0xFFEA580C), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ứng dụng bị cấm: $sampleName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9A3412))),
                        Text('Danh mục: $sampleCategory', style: const TextStyle(fontSize: 11, color: Color(0xFFC2410C))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Khi con mở ứng dụng cấm, Dịch vụ Trợ Năng (Accessibility) chạy ngầm sẽ ngay lập tức:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '1. Đá con văng ra khỏi ứng dụng bị cấm (Home).\n2. Bật màn hình khóa cưỡng chế che phủ màn hình.\n3. Phát cảnh báo khẩn cấp về điện thoại Ba Mẹ.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleBackgroundProhibitedAppDetected(appName: sampleName, category: sampleCategory);
            },
            child: const Text('Kích Hoạt Chặn Ngay'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getFamilyGroup(widget.username),
        _service.getMemberLocations(),
        _service.getAlerts(),
        _service.getChildRequests(),
        _service.getAppRules(),
        _service.getSchedules(),
        _service.getFamilyMembers(),
      ]);

      bool isLocked = false;
      String lockReason = '';
      try {
        final lockInfo = await _service.getChildLockInfo(widget.username);
        isLocked = lockInfo['isLocked'] == true;
        lockReason = lockInfo['reason']?.toString() ?? '';
      } catch (_) {}

      if (mounted) {
        setState(() {
          _group = results[0] as Map<String, dynamic>;
          _locations = results[1] as List<Map<String, dynamic>>;
          _alerts = results[2] as List<Map<String, dynamic>>;
          _childRequests = results[3] as List<Map<String, dynamic>>;
          _appRules = results[4] as List<Map<String, dynamic>>;
          _schedules = results[5] as List<Map<String, dynamic>>;
          _members = (results.length > 6 ? results[6] : []) as List<Map<String, dynamic>>;
          _isChildDeviceLocked = isLocked;
          _childLockReason = lockReason;
          _isLoading = false;
        });
        _syncScreenTimeFromServer();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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

  // ==============================================================
  // TÍCH LŨY & THEO DÕI THỜI GIAN SỬ DỤNG MÁY HÔM NAY (REAL-TIME SCREEN TIME)
  // ==============================================================
  Future<void> _initScreenTimeTracking() async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final storageKey = 'screen_time_${todayStr}_${widget.username.trim()}';

    // 1. Phục hồi số giây đã dùng hôm nay từ local SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSeconds = prefs.getInt(storageKey) ?? 0;
      if (mounted && savedSeconds > 0) {
        setState(() {
          _todayUsedSeconds = savedSeconds;
        });
      }
    } catch (e) {
      debugPrint('[SCREEN_TIME] Lỗi đọc SharedPreferences: $e');
    }

    // 2. Đồng bộ số liệu từ server
    await _syncScreenTimeFromServer();

    // 3. Khởi chạy Timer đếm thời gian sử dụng thực tế (mỗi 1 giây tăng 1s khi mở app)
    _screenTimeTrackerTimer?.cancel();
    _screenTimeTrackerTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      setState(() {
        _todayUsedSeconds++;
        final effectiveLimitSec = (_todayBaseLimitMinutes + _approvedExtraMinutes) * 60;
        if (effectiveLimitSec > 0 && _todayUsedSeconds >= effectiveLimitSec) {
          _isScreenTimeOverLimit = true;
        }
      });

      // Lưu định kỳ mỗi 15 giây vào SharedPreferences
      if (_todayUsedSeconds % 15 == 0) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(storageKey, _todayUsedSeconds);
        } catch (_) {}
      }
    });

    // 4. Định kỳ mỗi 60 giây gửi tích lũy 1 phút lên Server (cho tài khoản Con)
    _screenTimeServerSyncTimer?.cancel();
    if (isChildOrMember) {
      _screenTimeServerSyncTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
        if (!mounted) return;
        await _recordUsageToServer(additionalMinutes: 1, appName: 'Thiết bị');
      });
    }
  }

  Future<void> _syncScreenTimeFromServer() async {
    try {
      final targetUser = isOwner ? 'con' : widget.username;
      final stats = await _service.getScreenTimeStats(targetUser);
      if (mounted && stats.isNotEmpty) {
        final serverUsedMinutes = (stats['totalUsedMinutes'] as num?)?.toInt() ?? 0;
        final baseLimit = (stats['baseLimitMinutes'] as num?)?.toInt() ?? 120;
        final extraMinutes = (stats['approvedExtraMinutes'] as num?)?.toInt() ?? 0;
        final isOver = stats['isOverLimit'] == true;

        setState(() {
          _todayBaseLimitMinutes = baseLimit;
          _approvedExtraMinutes = extraMinutes;
          _isScreenTimeOverLimit = isOver;
          // Nếu server ghi nhận số phút dùng nhiều hơn local, đồng bộ theo server
          if (serverUsedMinutes * 60 > _todayUsedSeconds) {
            _todayUsedSeconds = serverUsedMinutes * 60;
          }
        });
      }
    } catch (e) {
      debugPrint('[SCREEN_TIME] Lỗi đồng bộ từ server: $e');
    }
  }

  Future<void> _recordUsageToServer({required int additionalMinutes, String? appName}) async {
    try {
      final targetUser = isOwner ? 'con' : widget.username;
      final res = await _service.recordUsage(
        childUsername: targetUser,
        additionalMinutes: additionalMinutes,
        appName: appName ?? 'Thiết bị',
      );
      if (mounted && res['success'] == true) {
        final totalUsed = (res['totalUsedMinutesToday'] as num?)?.toInt() ?? 0;
        final isOver = res['isOverLimit'] == true;
        setState(() {
          _isScreenTimeOverLimit = isOver;
          if (totalUsed * 60 > _todayUsedSeconds) {
            _todayUsedSeconds = totalUsed * 60;
          }
        });
      }
    } catch (e) {
      debugPrint('[SCREEN_TIME] Lỗi ghi nhận thời gian dùng: $e');
    }
  }

  Future<void> _simulateQuickUsage(int minutes) async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final storageKey = 'screen_time_${todayStr}_${widget.username.trim()}';

    setState(() {
      _todayUsedSeconds += minutes * 60;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(storageKey, _todayUsedSeconds);
    } catch (_) {}

    await _recordUsageToServer(additionalMinutes: minutes, appName: 'Mô phỏng sử dụng');
    await _syncScreenTimeFromServer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚡ Đã ghi nhận thêm $minutes phút sử dụng thiết bị hôm nay!'),
          backgroundColor: const Color(0xFF0D9488),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _resetTodayScreenTime() async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final storageKey = 'screen_time_${todayStr}_${widget.username.trim()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}

    setState(() {
      _todayUsedSeconds = 0;
      _isScreenTimeOverLimit = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Đã đặt lại bộ đếm thời gian sử dụng hôm nay về 00:00.'),
          backgroundColor: Color(0xFF64748B),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _parentGrantExtraMinutes(int minutes) async {
    try {
      final reqRes = await _service.sendChildRequest(
        childUsername: 'con',
        requestType: 'SCREEN_TIME',
        extraMinutes: minutes,
        note: 'Ba Mẹ chủ động cấp thêm giờ sử dụng',
      );
      if (reqRes['id'] != null) {
        await _service.handleChildRequest(reqRes['id'], 'APPROVE', widget.username);
      }
      await _syncScreenTimeFromServer();
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã cấp thêm $minutes phút sử dụng máy cho con hôm nay!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PARENT_GRANT] Lỗi: $e');
    }
  }

  Widget _buildQuickUsageChip(String label, int minutes) {
    return InkWell(
      onTap: () => _simulateQuickUsage(minutes),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
        ),
      ),
    );
  }

  Widget _buildParentScreenTimeMonitorCard() {
    final int usedMinutes = _todayUsedSeconds ~/ 60;
    final int effectiveDailyLimit = _todayBaseLimitMinutes + _approvedExtraMinutes;
    final double progress = effectiveDailyLimit > 0
        ? (usedMinutes / effectiveDailyLimit.toDouble()).clamp(0.0, 1.0)
        : 0.0;
    final bool isOver = (usedMinutes >= effectiveDailyLimit && effectiveDailyLimit > 0) || _isScreenTimeOverLimit;

    final Color statusColor = isOver
        ? const Color(0xFFDC2626)
        : (progress >= 0.8 ? const Color(0xFFEA580C) : const Color(0xFF0D9488));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.query_builder, color: statusColor, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Thời Gian Dùng Máy Hôm Nay Của Con',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    isOver ? 'ĐÃ HẾT GIỜ' : (progress >= 0.8 ? 'SẮP HẾT' : 'AN TOÀN'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Đã dùng: $usedMinutes phút',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor),
                ),
                Text(
                  'Hạn mức: $effectiveDailyLimit phút (${_todayBaseLimitMinutes}p gốc + ${_approvedExtraMinutes}p thêm)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Cấp thêm cho con:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('+15 Phút', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => _parentGrantExtraMinutes(15),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('+30 Phút', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => _parentGrantExtraMinutes(30),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Đồng bộ lại',
                  icon: const Icon(Icons.refresh, size: 20, color: AppTheme.textSecondary),
                  onPressed: () async {
                    await _syncScreenTimeFromServer();
                    await _loadAllData();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 1. TÍNH NĂNG CHIA SẺ VỊ TRÍ TỰ ĐỘNG LIÊN TỤC 24/7 (REAL-TIME CONTINUOUS TRACKING)
  // Cha Mẹ thấy vị trí con di chuyển liên tục, Con KHÔNG CẦN bấm gửi!
  // ==============================================================
  void _startContinuousLocationTracking() {
    // 1. Luôn lắng nghe lệnh Khóa / Mở Khóa thiết bị từ xa theo thời gian thực cho TẤT CẢ tài khoản
    _childLockPollTimer?.cancel();
    _childLockPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || isOwner) return;
      if (!mounted) return;
      try {
        final lockInfo = await _service.getChildLockInfo(widget.username);
        final isLocked = lockInfo['isLocked'] == true;
        final reason = lockInfo['reason']?.toString() ?? '';
        if (mounted && (_isChildDeviceLocked != isLocked || _childLockReason != reason)) {
          setState(() {
            _isChildDeviceLocked = isLocked;
            _childLockReason = reason;
          });
        }
      } catch (_) {}
    });

    if (isChildOrMember) {
      // 2. Phía Trẻ em: Tự động truyền tọa độ GPS lên server định kỳ mỗi 15 giây (hoàn toàn ngầm)
      _autoSendChildLocationSilently();
      _childAutoLocationTimer?.cancel();
      _childAutoLocationTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        _autoSendChildLocationSilently();
      });
    } else {
      // 3. Phía Ba Mẹ: Tự động đồng bộ vị trí các con liên tục
      _parentAutoRefreshTimer?.cancel();
      _parentAutoRefreshTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
        _autoRefreshLocationsSilently();
      });
    }
  }

  Future<void> _autoRefreshLocationsSilently() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        _service.getMemberLocations(),
        _service.getAlerts(),
        _service.getChildRequests(),
        _service.getFamilyMembers(),
      ]);
      if (mounted) {
        setState(() {
          _locations = results[0];
          _alerts = results[1];
          _childRequests = results[2];
          _members = results[3];
        });
      }
    } catch (_) {}
  }

  String _resolveAddressFromCoords(double lat, double lng) {
    if (lat >= 10.82 && lat <= 10.88 && lng >= 106.75 && lng <= 106.85) {
      return 'Khu Công Nghệ Cao, TP. Thủ Đức, TP. Hồ Chí Minh';
    } else if (lat >= 10.74 && lat <= 10.79 && lng >= 106.64 && lng <= 106.69) {
      return 'Quận 10, TP. Hồ Chí Minh';
    } else if (lat >= 10.77 && lat <= 10.82 && lng >= 106.69 && lng <= 106.73) {
      return 'Quận Bình Thạnh, TP. Hồ Chí Minh';
    } else if (lat >= 10.76 && lat <= 10.80 && lng >= 106.68 && lng <= 106.72) {
      return 'Quận 1, TP. Hồ Chí Minh';
    } else {
      return 'Tọa độ GPS (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}), TP.HCM';
    }
  }

  Future<void> _autoSendChildLocationSilently({
    double? overrideLat,
    double? overrideLng,
    String? overrideAddress,
    double? speed,
  }) async {
    if (!mounted) return;
    try {
      final lockInfo = await _service.getChildLockInfo(widget.username);
      final lockStatus = lockInfo['isLocked'] == true;
      final lockReason = lockInfo['reason']?.toString() ?? '';
      if (mounted && (_isChildDeviceLocked != lockStatus || _childLockReason != lockReason)) {
        setState(() {
          if (!isOwner) _isChildDeviceLocked = lockStatus;
          _childLockReason = lockReason;
        });
      }
    } catch (_) {}
    try {
      double lat = overrideLat ?? (10.846939 + (Random().nextDouble() - 0.5) * 0.0008);
      double lng = overrideLng ?? (106.775958 + (Random().nextDouble() - 0.5) * 0.0008);
      double curSpeed = speed ?? (Random().nextDouble() * 2.5 + 0.8);

      // Thử lấy vị trí thực từ GPS thiết bị nếu có quyền
      if (overrideLat == null) {
        try {
          final pos = await Geolocator.getLastKnownPosition();
          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            curSpeed = pos.speed > 0 ? pos.speed * 3.6 : curSpeed;
          }
        } catch (_) {}
      }

      String? vietmapAddress;
      if (overrideAddress == null) {
        try {
          vietmapAddress = await VietmapService.reverseGeocode(lat, lng);
        } catch (_) {}
      }
      String address = overrideAddress ?? vietmapAddress ?? _resolveAddressFromCoords(lat, lng);

      await _service.updateLocation(
        username: widget.username,
        latitude: lat,
        longitude: lng,
        speed: double.parse(curSpeed.toStringAsFixed(1)),
        address: address,
      );

      final lockStatus = await _service.getChildLockStatus(widget.username);

      if (mounted) {
        setState(() {
          _currentLat = lat;
          _currentLng = lng;
          _currentGpsText = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
          _currentAddressText = address;
          if (!isOwner) _isChildDeviceLocked = lockStatus;
        });
      }
    } catch (_) {}
  }

  Future<void> _shareMyLocation() async {
    setState(() => _isGettingLocation = true);
    await _autoSendChildLocationSilently();
    if (mounted) {
      setState(() => _isGettingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã cập nhật vị trí trực tiếp: $_currentAddressText'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadAllData();
    }
  }

  // ==============================================================
  // ==============================================================
  // 1.1 TÍNH NĂNG LÁ CHẮN TỰ ĐỘNG CHẶN MỌI TRUY CẬP & TẢI XUỐNG ĐỘC HẠI
  // Không cần phụ huynh phải gắn link vô kiểm tra thủ công!
  // ==============================================================
  Future<void> _handleAutoBlockEvent({
    required String targetName,
    required String actionType, // "DOWNLOAD" hoặc "ACCESS"
    required String category,
    required String reason,
    bool isAllowed = false,
  }) async {
    if (isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('✅ Cho phép tải/truy cập: "$targetName" (Nội dung học tập an toàn)')),
            ],
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      return;
    }

    // Gọi backend ghi nhận và tự động phát cảnh báo khẩn cấp đến Phụ huynh
    await _service.triggerAutoBlock(
      childUsername: widget.username,
      actionType: actionType,
      targetName: targetName,
      category: category,
    );

    final actionText = actionType == 'DOWNLOAD' ? 'tải xuống tệp nguy hiểm' : 'truy cập đường link độc hại';

    setState(() {
      _childWebHistory.insert(0, {
        'url': targetName,
        'title': 'Đã tự động chặn $actionText',
        'isBlocked': true,
        'category': category,
        'time': 'Vừa xong',
      });
    });

    if (!mounted) return;

    // Hiển thị Popup cảnh báo đỏ rực ngăn chặn ngay trên màn hình trẻ
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad, color: Color(0xFFDC2626), size: 34),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'LÁ CHẮN ĐÃ TỰ ĐỘNG CHẶN!',
                style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  Icon(actionType == 'DOWNLOAD' ? Icons.file_download_off : Icons.block, color: const Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      targetName,
                      style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Phân loại: $category',
              style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Lý do chặn: $reason',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active, color: Color(0xFF2563EB), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hệ thống đã tự động gửi cảnh báo an toàn đến Cha Mẹ ngay lập tức!',
                      style: TextStyle(color: Color(0xFF1E40AF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu & Trở về'),
          ),
        ],
      ),
    );

    _loadAllData();
  }

  // ==============================================================
  // 2. TÍNH NĂNG CẢM BIẾN TIẾNG ỒN CHẠY SUỐT 24/7 & LỌC NHIỄU BẢO VỆ CON
  // Đã quy định lọc xung âm ngắn (chuột, bàn phím, ho, nói chuyện bình thường)
  // Chỉ báo động khi có tiếng la hét kéo dài (>1.2s) hoặc va đập té ngã cực mạnh
  // ==============================================================
  void _startContinuousNoiseMonitoring() {
    _noiseTimer?.cancel();

    // Tự động khởi tạo kết nối Micro thực tế từ thiết bị/trình duyệt
    NoiseMeterService.instance.startListening(sensitivity: _noiseSensitivity).then((ok) {
      if (mounted) setState(() => _isRealMicActive = ok);
    });

    // Tần suất lấy mẫu 100ms
    _noiseTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;

      final isLive = NoiseMeterService.instance.isListening();
      if (isLive != _isRealMicActive && mounted) {
        setState(() => _isRealMicActive = isLive);
      }

      double measured;
      List<double> newWave;

      if (isLive) {
        // Lấy âm lượng Decibel trực tiếp từ Micro thực tế
        final liveDb = NoiseMeterService.instance.getDecibel();
        measured = liveDb > 0 ? liveDb : 38.0;
        final rawBars = NoiseMeterService.instance.getWaveform();
        newWave = rawBars.isNotEmpty ? rawBars : _audioWaveform;
      } else {
        // Dao động nền tự nhiên an toàn khi chưa cấp quyền mic (34 - 50 dB), không tự ý phát sinh xung giả gây báo ảo
        double base = 38.0 + sin(now / 400.0) * 3.5;
        double ambient = (Random().nextDouble() * 5.0) * _noiseSensitivity;
        measured = (base + ambient).clamp(30.0, 52.0);
        newWave = List<double>.generate(14, (i) {
          double f = sin((now / 150.0) + i * 0.8) * 10.0;
          return (measured * 0.55 + f + Random().nextDouble() * 6.0).clamp(10.0, 60.0);
        });
      }

      final yamnetRes = YamnetAudioSafetyService.instance.analyzeAudioFrame(
        decibel: measured,
        waveform: newWave,
        isLiveMic: isLive,
      );

      setState(() {
        _currentDecibel = double.parse(measured.toStringAsFixed(1));
        _audioWaveform = newWave;
        _lastYamnetResult = yamnetRes;
      });

      // BỘ LỌC ÂM THANH CHỐNG BÁO ẢO (INTELLIGENT NOISE FILTER):
      // Chỉ khi chạy micro thực tế và âm lượng vượt ngưỡng cảnh báo:
      if (isLive && _currentDecibel >= _noiseThreshold) {
        _consecutiveNoiseTicks++;

        // Điều kiện 1: Tiếng ồn vượt ngưỡng liên tục trong ít nhất 1.2 giây (12 ticks liên tiếp)
        // (Ví dụ: tiếng la hét kéo dài, tiếng còi hú khẩn cấp, tiếng máy móc gầm rú kéo dài)
        final bool isProlongedLoudNoise = _consecutiveNoiseTicks >= 12;

        // Điều kiện 2: Xung âm thanh va chạm cực mạnh (>= 92 dB) kéo dài ít nhất 300ms (3 ticks liên tiếp)
        // (Ví dụ: rơi vỡ kính lớn, va quẹt xe mạnh, té ngã nguy kịch)
        final bool isSevereCrashImpulse = _currentDecibel >= 92.0 && _consecutiveNoiseTicks >= 3;

        if (isProlongedLoudNoise || isSevereCrashImpulse) {
          _consecutiveNoiseTicks = 0; // Reset sau khi kích hoạt
          _triggerAutoNoiseAlert(
            db: _currentDecibel,
            incidentType: isSevereCrashImpulse
                ? 'Âm thanh va đập cực mạnh (${_currentDecibel.toStringAsFixed(1)} dB) vượt ngưỡng nguy cấp'
                : 'Tiếng la hét / Ồn lớn liên tục (${_currentDecibel.toStringAsFixed(1)} dB) vượt ngưỡng ${_noiseThreshold.toStringAsFixed(0)} dB',
          );
        }
      } else {
        // Âm thanh về mức bình thường thì hạ dần bộ đếm
        if (_consecutiveNoiseTicks > 0) {
          _consecutiveNoiseTicks--;
        }
      }
    });
  }

  Future<void> _triggerAutoNoiseAlert({
    required double db,
    required String incidentType,
    bool isManualSimulation = false,
    YamnetDetectionResult? yamnetResult,
  }) async {
    // Cơ chế Debounce: Tránh spam liên tục nếu tiếng ồn kéo dài (ít nhất 45 giây giữa các lần tự động)
    if (!isManualSimulation && _lastNoiseAlertTime != null) {
      final diff = DateTime.now().difference(_lastNoiseAlertTime!).inSeconds;
      if (diff < 45) return;
    }

    // Không hiển thị đè dialog nếu popup trước chưa được đóng
    if (_isNoiseDialogShowing) return;

    _lastNoiseAlertTime = DateTime.now();

    setState(() {
      _currentDecibel = db;
      _noiseIncidents.insert(0, {
        'db': db.toStringAsFixed(1),
        'type': incidentType,
        'time': 'Vừa xong',
        'status': 'ĐÃ GỬI BÁO ĐỘNG ĐẾN BA MẸ',
      });
    });

    // Lấy tọa độ GPS hiện tại
    double lat = 10.846939;
    double lng = 106.775958;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    // Gửi cảnh báo khẩn cấp lên Backend để Ba Mẹ nhận ngay lập tức
    await _service.sendSafetyAlert(
      username: widget.username,
      alertType: 'NOISE_ANOMALY',
      message: '🚨 [TIẾNG ỒN BẤT THƯỜNG] Âm lượng đạt ${db.toStringAsFixed(1)} dB (vượt ngưỡng ${_noiseThreshold.toStringAsFixed(0)} dB)! $incidentType. Vị trí: $_currentAddressText',
      latitude: lat,
      longitude: lng,
    );

    if (!mounted) return;

    // Hiển thị Popup cảnh báo khẩn cấp ngay trên màn hình trẻ
    _isNoiseDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 32),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'PHÁT HIỆN SỰ CỐ ÂM THANH!',
                style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, color: Color(0xFFDC2626), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mức âm lượng: ${db.toStringAsFixed(1)} dB',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF991B1B)),
                        ),
                        Text(
                          incidentType,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active, color: Color(0xFF2563EB), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hệ thống đã TỰ ĐỘNG phát tín hiệu báo động khẩn cấp & gửi vị trí của con đến Ba Mẹ!',
                      style: TextStyle(color: Color(0xFF1E40AF), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              _isNoiseDialogShowing = false;
              Navigator.pop(ctx);
            },
            child: const Text('Con Đã An Toàn'),
          ),
        ],
      ),
    ).then((_) {
      _isNoiseDialogShowing = false;
    });
  }

  // ==============================================================
  // 3. TÍNH NĂNG QUÉT MÃ QR (QR CODE SCANNER CAMERA)
  // ==============================================================
  void _openQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => SizedBox(
        height: 520,
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.black,
              title: const Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.purpleAccent),
                  SizedBox(width: 8),
                  Text('Camera Quét Mã QR Gia Đình'),
                ],
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Hướng camera về phía mã QR trên thiết bị của Chủ gia đình / Thành viên để nhận diện liên kết',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  errorBuilder: (context, error) {
                    return Container(
                      color: const Color(0xFF1E293B),
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam_off_outlined, color: Colors.amberAccent, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'Không thể mở Camera: ',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Trên trình duyệt Web hoặc máy không có Camera, vui lòng đóng cửa sổ này và sử dụng ô nhập mã mời hoặc nút mô phỏng bên dưới.',
                              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.keyboard_outlined, size: 18),
                              label: const Text('Đóng & Dùng Mã Thủ Công'),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final code = barcode.rawValue?.trim();
                      if (code != null && code.isNotEmpty) {
                        Navigator.pop(ctx);
                        _handleScannedQrResult(code);
                        break;
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _handleScannedQrResult(String code) async {
    String cleanCode = code.trim();
    if (cleanCode.toLowerCase().startsWith('family_invite:')) {
      cleanCode = cleanCode.substring('family_invite:'.length).trim();
    }
    if (cleanCode.contains('inviteCode')) {
      try {
        final decoded = jsonDecode(cleanCode);
        if (decoded is Map && decoded['inviteCode'] != null) {
          cleanCode = decoded['inviteCode'].toString().trim();
        }
      } catch (_) {}
    }

    if (isOwner) {
      _showQrAssignDialog(prefilledInviteCode: cleanCode);
    } else {
      // Con quét mã QR của Ba Mẹ để ghép nối vào nhóm gia đình
      final res = await _service.childJoinQr(
        childUsername: widget.username,
        inviteCode: cleanCode,
      );

      if (!mounted) return;

      if (res['status'] == true) {
        await _loadAllData();
        if (!mounted) return;
        final currentMembers = _getUnifiedFamilyMembers();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF10B981), width: 2),
            ),
            title: const Row(
              children: [
                Icon(Icons.verified, color: Color(0xFF16A34A), size: 30),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'THAM GIA NHÓM THÀNH CÔNG!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF166534)),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      res['message'] ?? 'Bạn đã tham gia thành công vào Không Gian Gia Đình!',
                      style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nhóm: ${_group['name'] ?? "Không Gian Gia Đình"} • Mã: $cleanCode',
                              style: const TextStyle(color: Color(0xFF166534), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '👨‍👩‍👧‍👦 Thành viên trong gia đình (${currentMembers.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    ...currentMembers.map((m) {
                      final uName = (m['username'] ?? '').toString();
                      final isSelf = uName.toLowerCase() == widget.username.toLowerCase();
                      final role = (m['role'] ?? 'Member').toString();
                      final isOwnerM = role.toLowerCase() == 'owner' || role.toLowerCase() == 'admin';
                      final isChildM = role.toLowerCase() == 'child';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isOwnerM
                                  ? const Color(0xFF8B5CF6)
                                  : (isChildM ? const Color(0xFF0284C7) : const Color(0xFF16A34A)),
                              child: Icon(
                                isOwnerM
                                    ? Icons.admin_panel_settings
                                    : (isChildM ? Icons.child_care : Icons.family_restroom),
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isSelf ? '$uName (Bạn)' : uName,
                                style: TextStyle(
                                  fontWeight: isSelf ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                  color: isSelf ? const Color(0xFF7C3AED) : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isOwnerM
                                    ? const Color(0xFFEDE9FE)
                                    : (isChildM ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isOwnerM ? '👑 Chủ gia đình' : (isChildM ? '🧒 Con yêu' : '👨‍👩‍👧 Thành viên'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOwnerM
                                      ? const Color(0xFF6D28D9)
                                      : (isChildM ? const Color(0xFF0369A1) : const Color(0xFF166534)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (isChildOrMember) {
                    _tabController.animateTo(4);
                  } else {
                    _tabController.animateTo(5);
                  }
                },
                child: const Text('Xem Danh Sách Thành Viên'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Mã QR không hợp lệ'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showQrAssignDialog({String? prefilledInviteCode}) {
    final memberCtrl = TextEditingController();
    String assignedRole = 'Member';
    final inviteCode = prefilledInviteCode ?? _group['inviteCode'] ?? 'FAM-123456';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('Phân Quyền Qua Mã QR'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mã QR gia đình: $inviteCode', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
              const SizedBox(height: 12),
              TextField(
                controller: memberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên thành viên quét QR',
                  hintText: 'Nhập tên tài khoản thành viên',
                  prefixIcon: Icon(Icons.person_add_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Chỉ định vai trò gia đình:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: assignedRole,
                dropdownColor: AppTheme.surface,
                items: const [
                  DropdownMenuItem(value: 'Member', child: Text('Thành viên gia đình (Member)')),
                  DropdownMenuItem(value: 'Child', child: Text('Trẻ em (Child)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() => assignedRole = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
              onPressed: () async {
                final member = memberCtrl.text.trim();
                if (member.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên tài khoản của thành viên cần phân quyền!'), backgroundColor: AppTheme.warning)); return; }
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final res = await _service.qrAssignRole(
                  ownerUsername: widget.username,
                  memberUsername: member,
                  assignedRole: assignedRole,
                  inviteCode: inviteCode,
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Đã phân quyền'),
                    backgroundColor: res['status'] == true ? AppTheme.success : AppTheme.error,
                  ),
                );
                _loadAllData();
              },
              child: const Text('Xác nhận phân quyền'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SOS & YÊU CẦU DÀNH CHO TRẺ EM (CHILD)
  // ==========================================
  Future<void> _triggerSos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('KÍCH HOẠT SOS KHẨN CẤP?'),
          ],
        ),
        content: const Text(
          'Tọa độ vị trí và thông báo khẩn cấp sẽ được gửi lập tức đến Cha Mẹ và Người giám hộ!',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('GỬI TÍN HIỆU NGAY'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _service.sendSafetyAlert(
        username: widget.username,
        alertType: 'SOS',
        message: 'Tín hiệu SOS khẩn cấp! Trẻ đang cần trợ giúp ngay lập tức!',
        latitude: 10.762622,
        longitude: 106.660172,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Đã kích hoạt còi báo động SOS!'),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
        _loadAllData();
      }
    }
  }

  void _showChildRequestDialog() {
    int minutes = 30;
    final noteCtrl = TextEditingController(text: 'Con xin thêm thời gian để làm bài tập');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Gửi Yêu Cầu Đến Cha Mẹ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chọn số phút xin thêm:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: minutes,
                dropdownColor: AppTheme.surface,
                items: const [
                  DropdownMenuItem(value: 15, child: Text('+ 15 Phút')),
                  DropdownMenuItem(value: 30, child: Text('+ 30 Phút')),
                  DropdownMenuItem(value: 60, child: Text('+ 60 Phút')),
                ],
                onChanged: (v) {
                  if (v != null) setModalState(() => minutes = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Lý do / Lời nhắn cho cha mẹ'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final res = await _service.sendChildRequest(
                  childUsername: widget.username,
                  requestType: 'SCREEN_TIME',
                  extraMinutes: minutes,
                  note: noteCtrl.text.trim(),
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Đã gửi yêu cầu'),
                    backgroundColor: AppTheme.success,
                  ),
                );
                _loadAllData();
              },
              child: const Text('Gửi yêu cầu'),
            ),
          ],
        ),
      ),
    );
  }



  // ==========================================
  // CRUD 2: QUẢN LÝ ỨNG DỤNG BỊ CHẶN / GIỚI HẠN (APP RULES)
  // ==========================================
  void _showAddAppRuleDialog([Map<String, dynamic>? editRule]) {
    final appNameCtrl = TextEditingController(text: editRule?['appName'] ?? '');
    int limitMins = editRule?['dailyLimitMinutes'] ?? 60;
    String category = editRule?['category'] ?? 'Mạng xã hội';
    bool isBlocked = editRule?['isBlocked'] ?? false;
    final isEdit = editRule != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.app_blocking, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Text(isEdit ? 'Sửa Giới Hạn App' : 'Giới Hạn Ứng Dụng'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: appNameCtrl,
                decoration: const InputDecoration(labelText: 'Tên App (vd: TikTok, Roblox, Facebook)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                dropdownColor: AppTheme.surface,
                items: const [
                  DropdownMenuItem(value: 'Mạng xã hội', child: Text('Mạng xã hội')),
                  DropdownMenuItem(value: 'Trò chơi', child: Text('Trò chơi (Games)')),
                  DropdownMenuItem(value: 'Giải trí', child: Text('Giải trí / Phim')),
                  DropdownMenuItem(value: 'Học tập', child: Text('Học tập')),
                ],
                onChanged: (v) {
                  if (v != null) setModalState(() => category = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Giới hạn: $limitMins phút/ngày', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Switch(
                    value: !isBlocked,
                    onChanged: (v) => setModalState(() => isBlocked = !v),
                  ),
                ],
              ),
              Slider(
                value: limitMins.toDouble(),
                min: 0,
                max: 180,
                divisions: 12,
                label: '$limitMins phút',
                onChanged: isBlocked ? null : (v) => setModalState(() => limitMins = v.toInt()),
              ),
              if (isBlocked)
                const Text('⚠️ Đang khóa chặn hoàn toàn ứng dụng này', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final name = appNameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);

                if (isEdit) {
                  await _service.updateAppRule(editRule['id'], {
                    'appName': name,
                    'category': category,
                    'dailyLimitMinutes': limitMins,
                    'isBlocked': isBlocked,
                  });
                } else {
                  await _service.createAppRule(
                    childUsername: 'testuser01',
                    appName: name,
                    appPackage: 'com.app.${name.toLowerCase()}',
                    dailyLimitMinutes: limitMins,
                    category: category,
                    isBlocked: isBlocked,
                  );
                }
                _loadAllData();
              },
              child: Text(isEdit ? 'Cập nhật' : 'Lưu quy tắc'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CRUD 3: QUẢN LÝ LỊCH TRÌNH SINH HOẠT (SCHEDULES)
  // ==========================================
  // ==========================================
  // HÀM TIỆN ÍCH KIỂM TRA LỊCH TRÌNH VỊ TRÍ & KHOẢNG CÁCH (HAVERSINE)
  // ==========================================
  double _calculateDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371e3; // Bán kính Trái Đất (mét)
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lon2 - lon1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  bool _isNowInSchedule(String startTime, String endTime, String? daysOfWeek) {
    try {
      final now = DateTime.now();
      final dayNames = {
        DateTime.monday: 'T2',
        DateTime.tuesday: 'T3',
        DateTime.wednesday: 'T4',
        DateTime.thursday: 'T5',
        DateTime.friday: 'T6',
        DateTime.saturday: 'T7',
        DateTime.sunday: 'CN',
      };
      final todayStr = dayNames[now.weekday] ?? 'T2';
      if (daysOfWeek != null && daysOfWeek.isNotEmpty && !daysOfWeek.contains(todayStr)) {
        return false;
      }

      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      final nowMin = now.hour * 60 + now.minute;

      if (startMin <= endMin) {
        return nowMin >= startMin && nowMin <= endMin;
      } else {
        return nowMin >= startMin || nowMin <= endMin;
      }
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _evaluateSchedulePresence(Map<String, dynamic> s) {
    final startTime = s['startTime'] ?? '07:30';
    final endTime = s['endTime'] ?? '11:30';
    final daysOfWeek = s['daysOfWeek'] ?? 'T2, T3, T4, T5, T6';
    final isRequire = s['requireLocationPresence'] == true;
    final targetLat = (s['targetLatitude'] is num) ? (s['targetLatitude'] as num).toDouble() : null;
    final targetLng = (s['targetLongitude'] is num) ? (s['targetLongitude'] as num).toDouble() : null;
    final radius = (s['targetRadiusMeters'] is num) ? (s['targetRadiusMeters'] as num).toDouble() : 300.0;
    final childName = s['childUsername'] ?? '';

    if (!isRequire || targetLat == null || targetLng == null) {
      return {
        'isRequireLocation': false,
        'statusText': 'Lịch sinh hoạt thường',
        'isAbsent': false,
        'isInSchedule': false,
      };
    }

    final isInSchedule = _isNowInSchedule(startTime, endTime, daysOfWeek);

    // Tìm tọa độ hiện tại của con
    final childLoc = _locations.firstWhere(
      (l) => l['username'] == childName,
      orElse: () => _locations.isNotEmpty ? _locations.first : {},
    );

    double? distance;
    if (childLoc.isNotEmpty && childLoc['latitude'] != null && childLoc['longitude'] != null) {
      final cLat = (childLoc['latitude'] as num).toDouble();
      final cLng = (childLoc['longitude'] as num).toDouble();
      distance = _calculateDistanceMeters(cLat, cLng, targetLat, targetLng);
    }

    if (!isInSchedule) {
      return {
        'isRequireLocation': true,
        'isInSchedule': false,
        'isAbsent': false,
        'distance': distance,
        'statusText': 'Ngoài khung giờ ($startTime - $endTime)',
        'badgeColor': const Color(0xFF64748B),
      };
    }

    if (distance != null) {
      if (distance <= radius) {
        return {
          'isRequireLocation': true,
          'isInSchedule': true,
          'isAbsent': false,
          'distance': distance,
          'statusText': '✅ ĐÃ CÓ MẶT AN TOÀN (Cách ${distance.round()}m)',
          'badgeColor': const Color(0xFF16A34A),
        };
      } else {
        return {
          'isRequireLocation': true,
          'isInSchedule': true,
          'isAbsent': true,
          'distance': distance,
          'statusText': '🚨 ĐANG VẮNG MẶT! (Cách ${distance.round()}m)',
          'badgeColor': const Color(0xFFDC2626),
        };
      }
    }

    return {
      'isRequireLocation': true,
      'isInSchedule': true,
      'isAbsent': false,
      'distance': null,
      'statusText': 'Đang kiểm tra tọa độ...',
      'badgeColor': const Color(0xFF0284C7),
    };
  }

  // ==========================================
  // CRUD 3: QUẢN LÝ LỊCH TRÌNH CÓ MẶT TẠI ĐỊA ĐIỂM (SCHEDULES & PRESENCE)
  // ==========================================
  void _showAddScheduleDialog([Map<String, dynamic>? editSched]) {
    final titleCtrl = TextEditingController(text: editSched?['title'] ?? 'Có mặt tại Trường Học');
    final locNameCtrl = TextEditingController(text: editSched?['targetLocationName'] ?? 'Trường Tiểu Học Tân Phú');
    final locAddressCtrl = TextEditingController(text: editSched?['targetAddress'] ?? 'Khu Công Nghệ Cao, TP. Thủ Đức, TP.HCM');

    final childrenList = _locations
        .where((l) => l['username'] != widget.username)
        .map((l) => l['username'].toString())
        .toSet()
        .toList();
    if (childrenList.isEmpty) {
      childrenList.add(widget.username);
    }

    String selectedChild = editSched?['childUsername'] ?? childrenList.first;
    String type = editSched?['scheduleType'] ?? 'LOCATION_PRESENCE';
    String start = editSched?['startTime'] ?? '07:30';
    String end = editSched?['endTime'] ?? '11:30';
    bool lock = editSched?['lockDeviceDuringSchedule'] ?? false;
    bool requireLocation = editSched?['requireLocationPresence'] ?? true;
    double targetLat = (editSched?['targetLatitude'] is num) ? (editSched!['targetLatitude'] as num).toDouble() : 10.8505;
    double targetLng = (editSched?['targetLongitude'] is num) ? (editSched!['targetLongitude'] as num).toDouble() : 106.7720;
    double targetRadius = (editSched?['targetRadiusMeters'] is num) ? (editSched!['targetRadiusMeters'] as num).toDouble() : 300.0;

    List<String> selectedDays = (editSched?['daysOfWeek'] != null)
        ? (editSched!['daysOfWeek'] as String).split(',').map((e) => e.trim()).toList()
        : ['T2', 'T3', 'T4', 'T5', 'T6'];

    final isEdit = editSched != null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_drop, color: Color(0xFF0284C7), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEdit ? 'Sửa Lịch Giám Sát Địa Điểm' : 'Cài Đặt Địa Điểm Bắt Buộc Có Mặt',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 580),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Chọn con
                  DropdownButtonFormField<String>(
                    initialValue: childrenList.contains(selectedChild) ? selectedChild : childrenList.first,
                    decoration: InputDecoration(
                      labelText: 'Bé áp dụng lịch trình',
                      prefixIcon: const Icon(Icons.child_care, color: Color(0xFF0284C7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: childrenList.map((c) => DropdownMenuItem(value: c, child: Text('Bé: $c'))).toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => selectedChild = v);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Tên lịch trình
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Tên lịch (vd: Có mặt tại trường, Học thêm)',
                      prefixIcon: const Icon(Icons.label_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CÔNG TẮC BẮT BUỘC CÓ MẶT TẠI ĐỊA ĐIỂM
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: requireLocation ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: requireLocation ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              requireLocation ? Icons.location_on : Icons.location_off,
                              color: requireLocation ? const Color(0xFF16A34A) : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Bắt buộc có mặt tại địa điểm này (Cảnh báo vắng mặt)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            Switch(
                              value: requireLocation,
                              activeThumbColor: const Color(0xFF16A34A),
                              onChanged: (v) => setModalState(() => requireLocation = v),
                            ),
                          ],
                        ),
                        if (requireLocation) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: locNameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Tên địa điểm (Trường học, Lớp học thêm...)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: locAddressCtrl,
                            decoration: InputDecoration(
                              labelText: 'Địa chỉ cụ thể',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Các địa điểm mẫu nhanh
                          const Text('Chọn nhanh vị trí:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: const Text('🏫 Trường TH Tân Phú', style: TextStyle(fontSize: 11)),
                                backgroundColor: const Color(0xFFE0F2FE),
                                onPressed: () {
                                  setModalState(() {
                                    locNameCtrl.text = 'Trường Tiểu Học Tân Phú';
                                    locAddressCtrl.text = 'Khu Công Nghệ Cao, TP. Thủ Đức, TP.HCM';
                                    targetLat = 10.8505;
                                    targetLng = 106.7720;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('📚 Lớp Học Thêm', style: TextStyle(fontSize: 11)),
                                backgroundColor: const Color(0xFFFEF3C7),
                                onPressed: () {
                                  setModalState(() {
                                    locNameCtrl.text = 'Trung Tâm Ngoại Ngữ Tân Phú';
                                    locAddressCtrl.text = 'Đường Lê Văn Việt, TP. Thủ Đức, TP.HCM';
                                    targetLat = 10.8420;
                                    targetLng = 106.7780;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('🏠 Nhà Riêng', style: TextStyle(fontSize: 11)),
                                backgroundColor: const Color(0xFFDCFCE7),
                                onPressed: () {
                                  setModalState(() {
                                    locNameCtrl.text = 'Nhà Riêng Gia Đình';
                                    locAddressCtrl.text = 'Khu Dân Cư Tân Phú, TP. Thủ Đức';
                                    targetLat = 10.846939;
                                    targetLng = 106.775958;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('📍 Vị trí hiện tại của con', style: TextStyle(fontSize: 11)),
                                backgroundColor: const Color(0xFFEDE9FE),
                                onPressed: () {
                                  final cLoc = _locations.firstWhere((l) => l['username'] == selectedChild, orElse: () => {});
                                  if (cLoc.isNotEmpty && cLoc['latitude'] != null) {
                                    setModalState(() {
                                      targetLat = (cLoc['latitude'] as num).toDouble();
                                      targetLng = (cLoc['longitude'] as num).toDouble();
                                      locAddressCtrl.text = cLoc['addressName'] ?? locAddressCtrl.text;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Bán kính cho phép
                          Row(
                            children: [
                              const Text('Bán kính cho phép:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              DropdownButton<double>(
                                value: targetRadius,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 100.0, child: Text('100 mét')),
                                  DropdownMenuItem(value: 200.0, child: Text('200 mét')),
                                  DropdownMenuItem(value: 300.0, child: Text('300 mét (Khuyên dùng)')),
                                  DropdownMenuItem(value: 500.0, child: Text('500 mét')),
                                  DropdownMenuItem(value: 1000.0, child: Text('1.000 mét (1 km)')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setModalState(() => targetRadius = v);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Xem trước Bản đồ VietMap của địa điểm
                          VietmapViewerWidget(
                            latitude: targetLat,
                            longitude: targetLng,
                            title: locNameCtrl.text.isNotEmpty ? locNameCtrl.text : 'Vị trí bắt buộc',
                            address: locAddressCtrl.text,
                            height: 140,
                            showControls: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Khung giờ: Từ giờ - Đến giờ
                  const Text('Khung Giờ Có Mặt:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: start,
                          decoration: InputDecoration(
                            labelText: 'Từ giờ',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: ['06:30', '07:00', '07:30', '08:00', '13:00', '13:30', '14:00', '17:30', '18:00', '19:00', '19:30', '20:00']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => start = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: end,
                          decoration: InputDecoration(
                            labelText: 'Đến giờ',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: ['08:30', '09:00', '11:00', '11:30', '12:00', '16:30', '17:00', '19:30', '20:00', '21:00', '21:30', '22:00']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => end = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Chọn ngày trong tuần
                  const Text('Ngày áp dụng:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'].map((d) {
                      final isSelected = selectedDays.contains(d);
                      return FilterChip(
                        label: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.textPrimary)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF0284C7),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedDays.add(d);
                            } else {
                              selectedDays.remove(d);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Khóa thiết bị con trong khung giờ này (Chỉ gọi khẩn cấp)', style: TextStyle(fontSize: 12)),
                    value: lock,
                    onChanged: (v) => setModalState(() => lock = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final messenger = ScaffoldMessenger.of(context);
                if (title.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập tên lịch trình')),
                  );
                  return;
                }
                Navigator.pop(ctx);

                final schedData = {
                  'childUsername': selectedChild,
                  'title': title,
                  'scheduleType': requireLocation ? 'LOCATION_PRESENCE' : type,
                  'startTime': start,
                  'endTime': end,
                  'daysOfWeek': selectedDays.join(', '),
                  'lockDeviceDuringSchedule': lock,
                  'isActive': true,
                  'requireLocationPresence': requireLocation,
                  'targetLocationName': locNameCtrl.text.trim(),
                  'targetAddress': locAddressCtrl.text.trim(),
                  'targetLatitude': targetLat,
                  'targetLongitude': targetLng,
                  'targetRadiusMeters': targetRadius,
                };

                if (isEdit) {
                  await _service.updateSchedule(editSched['id'], schedData);
                } else {
                  await _service.createSchedule(
                    childUsername: selectedChild,
                    title: title,
                    scheduleType: requireLocation ? 'LOCATION_PRESENCE' : type,
                    startTime: start,
                    endTime: end,
                    daysOfWeek: selectedDays.join(', '),
                    lockDevice: lock,
                    requireLocationPresence: requireLocation,
                    targetLocationName: locNameCtrl.text.trim(),
                    targetAddress: locAddressCtrl.text.trim(),
                    targetLatitude: targetLat,
                    targetLongitude: targetLng,
                    targetRadiusMeters: targetRadius,
                  );
                }

                // Kích hoạt đối chiếu ngay tức thì vị trí của con
                if (requireLocation) {
                  final cLoc = _locations.firstWhere((l) => l['username'] == selectedChild, orElse: () => {});
                  if (cLoc.isNotEmpty && cLoc['latitude'] != null) {
                    await _service.checkSchedulePresence(
                      childUsername: selectedChild,
                      latitude: (cLoc['latitude'] as num).toDouble(),
                      longitude: (cLoc['longitude'] as num).toDouble(),
                      addressName: cLoc['addressName'],
                    );
                  }
                }

                await _loadAllData();

                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('✅ Đã lưu lịch giám sát vị trí "${titleCtrl.text}" thành công!'),
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                );
              },
              child: Text(isEdit ? 'Cập Nhật' : 'Lưu Lịch Giám Sát'),
            ),
          ],
        ),
      ),
    );
  }

  // --- TRÒ CHUYỆN VỚI TRỢ LÝ AI ---
  Future<void> _sendAiMessage([void Function(void Function())? setModalState]) async {
    final text = _aiChatCtrl.text.trim();
    if (text.isEmpty) return;

    _aiChatCtrl.clear();
    setState(() {
      _aiChatMessages.add({'sender': 'user', 'text': text});
      _isAiReplying = true;
    });
    setModalState?.call(() {});

    final res = await _service.askAiAssistant(
      userRole: widget.role,
      username: widget.username,
      message: text,
    );

    if (mounted) {
      setState(() {
        _isAiReplying = false;
        _aiChatMessages.add({
          'sender': 'ai',
          'text': res['reply'] ?? 'Trợ lý AI đang bận, vui lòng thử lại sau.'
        });
      });
      setModalState?.call(() {});
    }
  }

  void _showAiAssistantBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              top: 16,
              left: 16,
              right: 16,
            ),
            child: SizedBox(
              height: 480,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 8),
                      const Text(
                        'Trợ Lý AI An Toàn Gia Đình',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: _aiChatMessages.isEmpty
                        ? const Center(
                            child: Text(
                              'Hãy đặt câu hỏi cho Trợ lý AI về an toàn trẻ em hoặc quản lý thiết bị!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _aiChatMessages.length,
                            itemBuilder: (ctx, i) {
                              final msg = _aiChatMessages[i];
                              final isUser = msg['sender'] == 'user';
                              return Align(
                                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isUser ? AppTheme.primary : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    msg['text'] ?? '',
                                    style: TextStyle(
                                      color: isUser ? Colors.white : AppTheme.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (_isAiReplying)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('AI đang suy nghĩ câu trả lời...', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _aiChatCtrl,
                            decoration: InputDecoration(
                              hintText: 'Nhập câu hỏi...',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: (_) => _sendAiMessage(setModalState),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: AppTheme.primary),
                          onPressed: () => _sendAiMessage(setModalState),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isTestLockActive || (_isChildDeviceLocked && !isOwner)) {
      return _buildChildLockedScreen(isTestMode: _isTestLockActive);
    }

    Color roleBadgeColor = isOwner ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black12,
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isOwner
                  ? (_group['name'] ?? 'Không Gian Gia Đình Đức Minh')
                  : (_group['name'] ?? 'Không Gian Gia Đình'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: roleBadgeColor),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    isOwner
                        ? '${widget.username} • Chủ Gia Đình'
                        : (isMember ? '${widget.username} • Thành Viên Gia Đình' : '${widget.username} • Con Yêu / Trẻ Em'),
                    style: TextStyle(color: roleBadgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Xem thành viên gia đình',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.people_alt_rounded, color: Color(0xFF0F766E), size: 22),
                if (_members.isNotEmpty)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '${_members.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showFamilyMembersBottomSheet,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Trợ lý AI An Toàn',
            icon: const Icon(Icons.smart_toy_outlined, color: Color(0xFF7C3AED), size: 21),
            onPressed: _showAiAssistantBottomSheet,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Làm mới dữ liệu',
            icon: const Icon(Icons.refresh, color: AppTheme.primary, size: 21),
            onPressed: _loadAllData,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 21),
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: isOwner ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: isOwner ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: isOwner
              ? [
                  Tab(
                    icon: const Icon(Icons.location_on_outlined, color: Colors.teal),
                    text: _childRequests.any((r) => (r['status'] ?? '').toString().toUpperCase() == 'PENDING')
                        ? '1. Vị Trí (${_childRequests.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'PENDING').length} Yêu cầu)'
                        : '1. Vị Trí Thành Viên',
                  ),
                  const Tab(icon: Icon(Icons.phonelink_lock, color: Colors.redAccent), text: '2. Khóa Máy Con'),
                  const Tab(icon: Icon(Icons.shield_outlined, color: Colors.redAccent), text: '3. Cảnh Báo Web Lạ'),
                  const Tab(icon: Icon(Icons.app_blocking_outlined, color: Colors.orange), text: '4. Giới Hạn App'),
                  const Tab(icon: Icon(Icons.schedule, color: Colors.teal), text: '5. Lịch Trình'),
                  const Tab(icon: Icon(Icons.groups_rounded, color: Colors.purpleAccent), text: '6. Thành Viên & Mã QR'),
                ]
              : [
                  Tab(icon: Icon(Icons.gpp_bad_outlined, color: Colors.redAccent), text: '1. Chặn Link Lạ & Web Độc'),
                  Tab(icon: Icon(Icons.mark_email_unread_outlined, color: Colors.blueAccent), text: '2. Hòm Thư & Tin Nhắn'),
                  Tab(icon: Icon(Icons.my_location, color: Colors.teal), text: '3. Vị Trí Của Con & SOS'),
                  Tab(icon: Icon(Icons.hourglass_bottom, color: Colors.orange), text: '4. Giới Hạn Giờ'),
                  Tab(icon: const Icon(Icons.groups_rounded, color: Colors.purpleAccent), text: _members.isNotEmpty ? '5. Thành Viên (${_members.length}) & Nhóm' : '5. Thành Viên & Nhóm'),
                ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: isOwner
                  ? [
                      _buildOwnerLocationTab(),
                      _buildOwnerDeviceLockTab(),
                      _buildOwnerWebFilterTab(),
                      _buildAppRulesTab(),
                      _buildSchedulesTab(),
                      _buildQrTab(),
                    ]
                  : [
                      _buildChildWebShieldTab(),
                      _buildChildNotificationsTab(),
                      _buildChildMyGpsAndSosTab(),
                      _buildChildScheduleAndLimitsTab(),
                      _buildChildQrScannerTab(),
                    ],
            ),
    );
  }

  // ==============================================================
  // TẬP HỢP TOÀN BỘ THÀNH VIÊN TRONG GIA ĐÌNH (OWNER, MEMBER, CHILD)
  // Đảm bảo tất cả thành viên khi tham gia nhóm gia đình đều xem được nhau!
  // ==============================================================
  List<Map<String, dynamic>> _getUnifiedFamilyMembers() {
    final Map<String, Map<String, dynamic>> memberMap = {};
    final String ownerName = (_group['ownerId'] ?? 'duc').toString().trim();
    final String currentUname = widget.username.trim();

    // 1. Nạp từ _members (chứa toàn bộ tài khoản người dùng từ server)
    for (final m in _members) {
      final uname = (m['username'] ?? '').toString().trim();
      if (uname.isEmpty) continue;
      final role = (m['role'] ?? '').toString().toLowerCase();
      if (role == 'customer' && uname.toLowerCase() != ownerName.toLowerCase() && uname.toLowerCase() != currentUname.toLowerCase()) {
        continue;
      }
      memberMap[uname.toLowerCase()] = Map<String, dynamic>.from(m);
    }

    // 2. Bổ sung / đồng bộ vị trí GPS tức thời từ _locations
    for (final l in _locations) {
      final uname = (l['username'] ?? '').toString().trim();
      if (uname.isEmpty) continue;
      final key = uname.toLowerCase();
      if (memberMap.containsKey(key)) {
        final existing = memberMap[key]!;
        if (l['latitude'] != null) existing['latitude'] = l['latitude'];
        if (l['longitude'] != null) existing['longitude'] = l['longitude'];
        if (l['speed'] != null) existing['speed'] = l['speed'];
        if (l['addressName'] != null) existing['addressName'] = l['addressName'];
        if (l['updatedAt'] != null) existing['updatedAt'] = l['updatedAt'];
        existing['hasLocation'] = true;
        if (l['isDeviceLocked'] != null) {
          existing['isDeviceLocked'] = l['isDeviceLocked'];
        }
      } else {
        final role = (l['role'] ?? '').toString().toLowerCase();
        if (role != 'customer' || uname.toLowerCase() == ownerName.toLowerCase() || uname.toLowerCase() == currentUname.toLowerCase()) {
          memberMap[key] = Map<String, dynamic>.from(l);
        }
      }
    }

    // 3. Đảm bảo Chủ nhóm (Owner) luôn có trong danh sách
    if (ownerName.isNotEmpty && !memberMap.containsKey(ownerName.toLowerCase())) {
      memberMap[ownerName.toLowerCase()] = {
        'username': ownerName,
        'role': 'Owner',
        'hasLocation': false,
        'addressName': 'Chủ gia đình',
      };
    }

    // 4. Đảm bảo tài khoản người dùng hiện tại luôn có mặt
    if (currentUname.isNotEmpty && !memberMap.containsKey(currentUname.toLowerCase())) {
      memberMap[currentUname.toLowerCase()] = {
        'username': currentUname,
        'role': widget.role,
        'hasLocation': true,
        'latitude': _currentLat,
        'longitude': _currentLng,
        'addressName': _currentAddressText,
        'speed': 0.0,
        'isDeviceLocked': _isChildDeviceLocked,
      };
    }

    // 5. Sắp xếp: Chủ gia đình (Owner) -> Thành viên (Member) -> Trẻ em (Child)
    final list = memberMap.values.toList();
    list.sort((a, b) {
      final roleA = (a['role'] ?? '').toString().toLowerCase();
      final roleB = (b['role'] ?? '').toString().toLowerCase();

      int score(String r) {
        if (r == 'owner' || r == 'admin') return 1;
        if (r == 'member') return 2;
        if (r == 'child') return 3;
        return 4;
      }

      final cmp = score(roleA).compareTo(score(roleB));
      if (cmp != 0) return cmp;
      return (a['username'] ?? '').toString().compareTo((b['username'] ?? '').toString());
    });

    return list;
  }

  void _showFamilyMembersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildFamilyMembersListWidget(isOwnerView: isOwner),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyMembersListWidget({
    bool isOwnerView = false,
    bool isLocationTab = false,
  }) {
    final members = _getUnifiedFamilyMembers();
    final groupName = _group['name'] ?? 'Không Gian Gia Đình Đức Minh';
    final inviteCode = _group['inviteCode'] ?? 'FAM-769610';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Card danh sách thành viên gia đình
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '👨‍👩‍👧‍👦 THÀNH VIÊN TRONG GIA ĐÌNH (${members.length})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhóm: $groupName • Mã: $inviteCode',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                tooltip: 'Cập nhật thành viên',
                onPressed: () {
                  _loadAllData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đang cập nhật danh sách thành viên gia đình...'),
                      duration: Duration(milliseconds: 900),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Danh sách từng thành viên
        if (members.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.group_off_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Chưa có thành viên nào trong nhóm',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hãy chia sẻ mã mời "$inviteCode" hoặc quét mã QR để người thân cùng tham gia Không Gian Gia Đình!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          ...members.map((m) {
            final memberName = (m['username'] ?? 'Thành viên').toString();
            final isMemberSelf = memberName.toLowerCase() == widget.username.toLowerCase();
            final memberRole = (m['role'] ?? (isMemberSelf ? widget.role : 'Member')).toString();
            final isChildRole = memberRole.toLowerCase() == 'child';
            final isOwnerRole = memberRole.toLowerCase() == 'owner' || memberRole.toLowerCase() == 'admin';
            final hasLoc = m['hasLocation'] == true || m['latitude'] != null;
            final address = (m['addressName'] ?? 'Chưa có dữ liệu vị trí GPS').toString();
            final speed = (m['speed'] is num) ? (m['speed'] as num).toDouble() : 0.0;
            final isLocked = m['isDeviceLocked'] == true;

            String roleDisplayName;
            Color roleBgColor;
            Color roleTextColor;
            IconData roleIcon;
            if (isOwnerRole) {
              roleDisplayName = '👑 Chủ Gia Đình (Ba Mẹ)';
              roleBgColor = const Color(0xFFEDE9FE);
              roleTextColor = const Color(0xFF6D28D9);
              roleIcon = Icons.admin_panel_settings;
            } else if (isChildRole) {
              roleDisplayName = '🧒 Con Yêu / Trẻ Em';
              roleBgColor = const Color(0xFFE0F2FE);
              roleTextColor = const Color(0xFF0369A1);
              roleIcon = Icons.child_care;
            } else {
              roleDisplayName = '👨‍👩‍👧 Thành Viên Gia Đình';
              roleBgColor = const Color(0xFFDCFCE7);
              roleTextColor = const Color(0xFF166534);
              roleIcon = Icons.family_restroom;
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isMemberSelf
                      ? const Color(0xFF8B5CF6)
                      : (isChildRole ? const Color(0xFFBAE6FD) : const Color(0xFFBBF7D0)),
                  width: isMemberSelf ? 1.8 : 1.2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    onTap: () => _showMemberLocationDetail(m),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: isOwnerRole
                          ? const Color(0xFF8B5CF6)
                          : (isChildRole ? const Color(0xFF0284C7) : const Color(0xFF16A34A)),
                      child: Icon(roleIcon, color: Colors.white, size: 22),
                    ),
                    title: Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (memberName.isNotEmpty)
                          Text(
                            memberName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        if (isMemberSelf)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Bạn',
                              style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            roleDisplayName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: roleTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                hasLoc ? Icons.location_on : Icons.location_off_outlined,
                                size: 14,
                                color: hasLoc ? const Color(0xFF0F766E) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: hasLoc ? FontWeight.w600 : FontWeight.normal,
                                    color: hasLoc ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (hasLoc && m['latitude'] != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '🌐 Tọa độ: ${(m['latitude'] as num).toDouble().toStringAsFixed(4)}, ${(m['longitude'] as num).toDouble().toStringAsFixed(4)}  •  ⚡ $speed km/h',
                              style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (isChildRole) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLocked ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isLocked ? '🔒 Thiết bị: ĐANG BỊ KHÓA TỪ XA' : '🟢 Thiết bị: Hoạt động bình thường',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isLocked ? const Color(0xFF991B1B) : const Color(0xFF166534),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isOwner && !isMemberSelf)
                          IconButton(
                            icon: const Icon(Icons.manage_accounts, color: Color(0xFF7C3AED), size: 20),
                            tooltip: 'Phân quyền Thành viên / Trẻ em',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showChangeMemberRoleDialog(memberName, memberRole),
                          ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasLoc ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 1,
                          ),
                          icon: const Icon(Icons.map, size: 13),
                          label: const Text('Bản đồ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                          onPressed: () => _showMemberLocationDetail(m),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, size: 13, color: Color(0xFF16A34A)),
                        const SizedBox(width: 4),
                        const Text(
                          'Đã tham gia Không Gian Gia Đình',
                          style: TextStyle(fontSize: 10, color: Color(0xFF166534), fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.touch_app, size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 2),
                        const Text(
                          'Chạm để xem chi tiết',
                          style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }


  // ==============================================================
  // A. VAI TRÒ CHỦ GIA ĐÌNH: 1. THEO DÕI VỊ TRÍ TẤT CẢ THÀNH VIÊN
  // ==============================================================
  void _showMemberLocationDetail(Map<String, dynamic> member) {
    final memberName = member['username'] ?? 'Thành viên';
    final address = member['addressName'] ?? 'Khu Công Nghệ Cao, TP. Thủ Đức, TP. Hồ Chí Minh';
    final double lat = (member['latitude'] is num) ? (member['latitude'] as num).toDouble() : 10.846939;
    final double lng = (member['longitude'] is num) ? (member['longitude'] as num).toDouble() : 106.775958;
    final double speed = (member['speed'] is num) ? (member['speed'] as num).toDouble() : 0.0;
    final isMemberSelf = member['username'] == widget.username;
    final rawRole = (member['role'] ?? (isMemberSelf ? 'Owner' : 'Member')).toString();
    final bool isChild = rawRole.toLowerCase() == 'child';
    final bool isOwnerRole = rawRole.toLowerCase() == 'owner' || rawRole.toLowerCase() == 'admin';
    final bool isChildLocked = member['isDeviceLocked'] == true;

    String roleTitle;
    Color roleBg;
    Color roleText;
    IconData roleIcon;

    if (isOwnerRole) {
      roleTitle = 'Chủ Gia Đình (Ba Mẹ)';
      roleBg = const Color(0xFFEDE9FE);
      roleText = const Color(0xFF6D28D9);
      roleIcon = Icons.admin_panel_settings;
    } else if (isChild) {
      roleTitle = 'Trẻ Em (Child - Giám Sát)';
      roleBg = const Color(0xFFE0F2FE);
      roleText = const Color(0xFF0369A1);
      roleIcon = Icons.child_care;
    } else {
      roleTitle = 'Thành Viên Gia Đình (Member)';
      roleBg = const Color(0xFFDCFCE7);
      roleText = const Color(0xFF166534);
      roleIcon = Icons.family_restroom;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isOwnerRole ? const Color(0xFF7C3AED) : (isChild ? const Color(0xFF0284C7) : const Color(0xFF16A34A)),
                    child: Icon(roleIcon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memberName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: roleBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                roleTitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: roleText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('🟢 VietMap Live', style: TextStyle(color: Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),

              // BẢN ĐỒ VIETMAP TRỰC TIẾP (VIETMAP STATIC/LIVE MAP)
              VietmapViewerWidget(
                latitude: lat,
                longitude: lng,
                title: memberName,
                address: address,
                height: 230,
                showControls: true,
                onFullScreen: () {
                  Navigator.pop(ctx);
                  VietmapFullScreenDialog.show(
                    context,
                    memberName: memberName,
                    roleName: roleTitle,
                    latitude: lat,
                    longitude: lng,
                    address: address,
                    speed: speed,
                  );
                },
              ),
              const SizedBox(height: 14),

              // Thẻ Vị Trí & Tọa độ GPS
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place, color: Color(0xFF16A34A), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF14532D)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text('Tọa độ VietMap: $lat, $lng', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 14, color: Color(0xFF0284C7)),
                        const SizedBox(width: 4),
                        Text('Vận tốc: $speed km/h • Trạng thái di chuyển bình thường', style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Nút Thao Tác Nhanh
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Chỉ Đường Đến Con', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        VietmapService.openDirectionsToChild(lat, lng, childName: memberName);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE0F2FE),
                      foregroundColor: const Color(0xFF0369A1),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.fullscreen),
                    tooltip: 'Xem bản đồ lớn',
                    onPressed: () {
                      Navigator.pop(ctx);
                      VietmapFullScreenDialog.show(
                        context,
                        memberName: memberName,
                        roleName: roleTitle,
                        latitude: lat,
                        longitude: lng,
                        address: address,
                        speed: speed,
                      );
                    },
                  ),
                  
                ],
              ),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0369A1),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.timeline, size: 20),
                  label: const Text('Xem Lịch Sử Lộ Trình Trong Ngày', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showLocationHistoryDialog(memberName);
                  },
                ),
              ),

              // Nút Khóa / Mở Khóa Điện Thoại Con từ xa
              if (isOwner && !isMemberSelf) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isChildLocked ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: Icon(isChildLocked ? Icons.lock_open : Icons.phonelink_lock, size: 20),
                    label: Text(
                      isChildLocked ? '🔓 MỞ KHÓA ĐIỆN THOẠI CHO $memberName' : '🔒 KHÓA ĐIỆN THOẠI $memberName TỪ XA',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (isChildLocked) {
                        final res = await _service.setChildLock(
                          childUsername: memberName,
                          isLocked: false,
                        );
                        if (memberName.toLowerCase() == widget.username.toLowerCase()) {
                          setState(() {
                            _isChildDeviceLocked = false;
                          _isTestLockActive = false;
                            _childLockReason = '';
                          });
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? 'Đã mở khóa điện thoại con!'),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                        _loadAllData();
                      } else {
                        _promptLockChildDevice(memberName);
                      }
                    },
                  ),
                ),
              ],

              // Nút Phân Quyền Thành Viên / Trẻ Em dành riêng cho Chủ Gia Đình (Owner)
              if (isOwner && !isMemberSelf) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.manage_accounts, size: 20),
                    label: Text(
                      'Phân Quyền Vai Trò (Chủ Gia Đình / Thành Viên / Trẻ Em)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showChangeMemberRoleDialog(memberName, rawRole);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Hộp thoại Phân quyền Thành viên hoặc Trẻ em dành riêng cho Chủ gia đình
  /// Hộp thoại Phân quyền Thành viên, Trẻ em, hoặc Chủ gia đình (Tối đa 2 Chủ: Ba & Mẹ)
  void _showChangeMemberRoleDialog(String memberName, String currentRole) {
    // Xác định vai trò hiện tại
    final String rawRole = currentRole.trim();
    final bool isMemberCurrentlyOwner = rawRole.toLowerCase() == 'owner' ||
        rawRole.toLowerCase() == 'admin' ||
        memberName.toLowerCase() == (_group['ownerId'] ?? '').toString().toLowerCase();

    String selected = 'Member';
    if (isMemberCurrentlyOwner) {
      selected = 'Owner';
    } else if (rawRole.toLowerCase() == 'child') {
      selected = 'Child';
    }

    // Đếm số lượng Chủ gia đình hiện có trong nhóm
    final allMembers = _getUnifiedFamilyMembers();
    final ownerMembers = allMembers.where((m) {
      final r = (m['role'] ?? '').toString().toLowerCase();
      final u = (m['username'] ?? '').toString().toLowerCase();
      final o = (_group['ownerId'] ?? '').toString().toLowerCase();
      return r == 'owner' || r == 'admin' || (o.isNotEmpty && u == o);
    }).toList();

    final int currentOwnerCount = ownerMembers.length;
    final bool isOwnerLimitReached = currentOwnerCount >= 2 && !isMemberCurrentlyOwner;
    final bool isSoleOwner = isMemberCurrentlyOwner && currentOwnerCount <= 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFEDE9FE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.manage_accounts, color: Color(0xFF7C3AED), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Phân Quyền Gia Đình', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Tài khoản: $memberName', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner thông báo giới hạn tối đa 2 chủ
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isOwnerLimitReached ? const Color(0xFFFEF2F2) : const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isOwnerLimitReached ? const Color(0xFFFCA5A5) : const Color(0xFFDDD6FE),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOwnerLimitReached ? Icons.info_outline : Icons.admin_panel_settings,
                        color: isOwnerLimitReached ? const Color(0xFFDC2626) : const Color(0xFF7C3AED),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOwnerLimitReached
                              ? 'Đã đủ 2/2 Chủ gia đình (Ba & Mẹ). Muốn nâng quyền tài khoản này, vui lòng chuyển bớt một Chủ khác sang Thành viên.'
                              : 'Chủ gia đình: $currentOwnerCount/2 (Tối đa 2 tài khoản Chủ: Ba & Mẹ).',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOwnerLimitReached ? const Color(0xFF991B1B) : const Color(0xFF5B21B6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Text('Chọn vai trò áp dụng cho thành viên này:', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                const SizedBox(height: 12),

                // Tùy chọn 1: Chủ gia đình (Owner / Ba Mẹ) - Tối đa 2 tài khoản
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isOwnerLimitReached) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Nhóm gia đình đã có đủ tối đa 2 tài khoản Chủ (Ba và Mẹ). Vui lòng hạ bớt một Chủ sang Thành viên trước!'),
                          backgroundColor: Color(0xFFDC2626),
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    setModalState(() => selected = 'Owner');
                  },
                  child: Opacity(
                    opacity: isOwnerLimitReached ? 0.6 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected == 'Owner' ? const Color(0xFFF5F3FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == 'Owner' ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
                          width: selected == 'Owner' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings, color: selected == 'Owner' ? const Color(0xFF7C3AED) : Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Chủ gia đình (Owner / Ba Mẹ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5B21B6))),
                                    if (isOwnerLimitReached) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFCA5A5)),
                                        ),
                                        child: const Text('Đủ 2/2 Chủ', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text('Quản trị toàn diện, xem vị trí thành viên, đặt giới hạn app & khóa máy con', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected == 'Owner' ? const Color(0xFF7C3AED) : Colors.grey.shade400,
                                width: selected == 'Owner' ? 6 : 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Tùy chọn 2: Thành viên gia đình (Member)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isSoleOwner) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Không thể hạ quyền tài khoản Chủ duy nhất! Nhóm gia đình cần ít nhất 1 Chủ để quản lý.'),
                          backgroundColor: Color(0xFFDC2626),
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    setModalState(() => selected = 'Member');
                  },
                  child: Opacity(
                    opacity: isSoleOwner ? 0.6 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected == 'Member' ? const Color(0xFFF0FDF4) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == 'Member' ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
                          width: selected == 'Member' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.family_restroom, color: selected == 'Member' ? const Color(0xFF16A34A) : Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Thành viên gia đình (Member)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534))),
                                    if (isSoleOwner) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('Chủ duy nhất', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text('Chia sẻ vị trí với gia đình, không bị giới hạn ứng dụng hay khóa máy', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected == 'Member' ? const Color(0xFF16A34A) : Colors.grey.shade400,
                                width: selected == 'Member' ? 6 : 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Tùy chọn 3: Trẻ em (Child)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isSoleOwner) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Không thể hạ quyền tài khoản Chủ duy nhất! Nhóm gia đình cần ít nhất 1 Chủ để quản lý.'),
                          backgroundColor: Color(0xFFDC2626),
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    setModalState(() => selected = 'Child');
                  },
                  child: Opacity(
                    opacity: isSoleOwner ? 0.6 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected == 'Child' ? const Color(0xFFE0F2FE) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == 'Child' ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                          width: selected == 'Child' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.child_care, color: selected == 'Child' ? const Color(0xFF0284C7) : Colors.grey),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Trẻ em (Child - Bảo Vệ Toàn Diện)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0369A1))),
                                SizedBox(height: 2),
                                Text('Chặn web độc, cảm biến đo tiếng ồn & SOS, đếm giờ dùng máy & khóa từ xa', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected == 'Child' ? const Color(0xFF0284C7) : Colors.grey.shade400,
                                width: selected == 'Child' ? 6 : 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final res = await _service.assignMemberRole(
                  ownerUsername: widget.username,
                  memberUsername: memberName,
                  assignedRole: selected,
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Đã cập nhật phân quyền thành công!'),
                    backgroundColor: res['status'] == true ? AppTheme.success : AppTheme.error,
                    duration: const Duration(seconds: 3),
                  ),
                );
                _loadAllData();
              },
              child: const Text('Lưu Phân Quyền'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationHistoryDialog(String childUsername) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0F2FE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.timeline, color: Color(0xFF0284C7), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lịch Sử Lộ Trình Di Chuyển',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Thành viên: $childUsername • Hôm nay',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              // Content FutureBuilder
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _service.getLocationHistory(childUsername),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final history = snapshot.data ?? [];
                    if (history.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.route_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text(
                                'Chưa có lịch sử di chuyển trong ngày',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Khi $childUsername di chuyển hoặc đổi vị trí, hệ thống sẽ tự động vẽ lộ trình thời gian thực tại đây.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final hLat = (item['latitude'] as num?)?.toDouble() ?? 10.8469;
                        final hLng = (item['longitude'] as num?)?.toDouble() ?? 106.7759;
                        final hSpeed = (item['speed'] as num?)?.toDouble() ?? 0.0;
                        final hAddress = item['addressName'] as String? ?? 'Đang cập nhật';
                        final hRecordedAt = item['recordedAt'] as String?;
                        String timeText = '';
                        if (hRecordedAt != null) {
                          try {
                            final dt = DateTime.parse(hRecordedAt).toLocal();
                            timeText = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          } catch (_) {
                            timeText = hRecordedAt;
                          }
                        }

                        final isFirst = index == 0;
                        final isLatest = index == history.length - 1;

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Timeline vertical line + icon
                              SizedBox(
                                width: 44,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isLatest
                                            ? Colors.red
                                            : (isFirst ? Colors.green : const Color(0xFF0284C7)),
                                      ),
                                      child: Icon(
                                        isLatest
                                            ? Icons.my_location
                                            : (isFirst ? Icons.play_arrow : Icons.fiber_manual_record),
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (!isLatest)
                                      Expanded(
                                        child: Container(
                                          width: 2,
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Card content
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isLatest ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isLatest ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.access_time, size: 14, color: AppTheme.textSecondary),
                                              const SizedBox(width: 4),
                                              Text(
                                                timeText,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              if (isLatest) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text('Hiện tại', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                              if (isFirst && !isLatest) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text('Bắt đầu', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (hSpeed > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE0F2FE),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$hSpeed km/h',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        hAddress,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () {
                                          VietmapFullScreenDialog.show(
                                            context,
                                            memberName: childUsername,
                                            roleName: 'Lộ trình lúc $timeText',
                                            latitude: hLat,
                                            longitude: hLng,
                                            address: hAddress,
                                            speed: hSpeed,
                                          );
                                        },
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.map, size: 14, color: Color(0xFF0284C7)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Xem trên bản đồ VietMap',
                                              style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerLocationTab() {
    // Sắp xếp: Chưa kiểm tra (isResolved == false) lên đầu hiển thị màu ĐỎ, Đã kiểm tra (isResolved == true) xuống dưới hiển thị màu XANH
    final sortedAlerts = List<Map<String, dynamic>>.from(_alerts)
      ..sort((a, b) {
        final aResolved = a['isResolved'] == true ? 1 : 0;
        final bResolved = b['isResolved'] == true ? 1 : 0;
        return aResolved.compareTo(bResolved);
      });
    final pendingRequests = _childRequests.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'PENDING').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Trạng thái Cảm biến Tiếng ồn & Vị trí 24/7 của các con
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.hearing, color: Colors.white, size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cảm Biến Tiếng Ồn Của Con: BẬT SUỐT 24/7',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '🟢 Tự động giám sát âm thanh môi trường và phát hiện la hét / va chạm (>82 dB) để báo ngay cho Ba Mẹ.',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // YÊU CẦU XIN THÊM GIỜ CHỜ PHÊ DUYỆT TỪ CON (ĐẶT Ở VỊ TRÍ CAO NHẤT ĐỂ BA MẸ KHÔNG BỊ BỎ LỠ)
          if (pendingRequests.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
                boxShadow: [
                  BoxShadow(color: Colors.amber.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFDE68A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_email_unread, color: Color(0xFFB45309), size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📩 YÊU CẦU MỚI TỪ CON CẦN PHÊ DUYỆT',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF92400E), fontSize: 14),
                            ),
                            Text(
                              'Có ${pendingRequests.length} yêu cầu xin thêm giờ đang chờ Ba Mẹ xử lý',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${pendingRequests.length} MỚI', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...pendingRequests.map((req) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_circle, color: Color(0xFF0284C7), size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  'Bé: ${req['childUsername'] ?? "Con yêu"}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '+${req['extraMinutes']} phút',
                                    style: const TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '📝 Lý do: "${req['note'] ?? "Con xin thêm giờ học nhóm"}"',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563), fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(color: Colors.redAccent),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.close, size: 16),
                                  label: const Text('Từ chối'),
                                  onPressed: () async {
                                    await _service.handleChildRequest(req['id'], 'REJECT', widget.username);
                                    _loadAllData();
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Duyệt Ngay'),
                                  onPressed: () async {
                                    await _service.handleChildRequest(req['id'], 'APPROVE', widget.username);
                                    _loadAllData();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],

          // Danh sách Cảnh báo Khẩn cấp & Tiếng ồn bất thường
          // Yêu cầu: Đã check rồi chuyển qua màu XANH, chưa check mới màu ĐỎ
          if (sortedAlerts.isNotEmpty) ...[
            ...sortedAlerts.map((alert) {
              final isResolved = alert['isResolved'] == true;
              final isNoise = alert['alertType'] == 'NOISE_ANOMALY' || alert['alertType'] == 'NOISE';
              final isSos = alert['alertType'] == 'SOS';
              final isAbsence = alert['alertType'] == 'ABSENCE_ALERT';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isResolved ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isResolved ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isResolved
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.redAccent.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isResolved ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isResolved
                                ? Icons.check_circle
                                : (isAbsence
                                    ? Icons.wrong_location
                                    : (isNoise ? Icons.volume_up : (isSos ? Icons.warning_rounded : Icons.gpp_bad))),
                            color: isResolved ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isResolved
                                    ? (isAbsence
                                        ? '📍 VẮNG MẶT ĐÃ KIỂM TRA'
                                        : (isNoise
                                            ? '🔊 TIẾNG ỒN ĐÃ ĐƯỢC KIỂM TRA'
                                            : (isSos ? '🆘 BÁO ĐỘNG SOS (ĐÃ KIỂM TRA)' : '🛡️ CẢNH BÁO AN TOÀN (ĐÃ KIỂM TRA)')))
                                    : (isAbsence
                                        ? '🚨 CẢNH BÁO VẮNG MẶT ĐỊA ĐIỂM BẮT BUỘC'
                                        : (isNoise
                                            ? '🚨 CẢNH BÁO TIẾNG ỒN BẤT THƯỜNG'
                                            : (isSos ? '🆘 BÁO ĐỘNG SOS KHẨN CẤP' : '🛡️ PHÁT HIỆN NGUY CƠ AN TOÀN'))),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: isResolved ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Thiết bị của con: ${alert['username'] ?? "Trẻ em"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isResolved ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isResolved ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isResolved ? 'ĐÃ KIỂM TRA' : 'CẦN XỬ LÝ',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((alert['message'] ?? '').toString().contains('YAMNET') || (alert['alertType'] ?? '').toString().contains('YAMNET')) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.psychology, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'AI GOOGLE YAMNET SỰ CỐ ÂM THANH',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(
                      alert['message'] ?? 'Phát hiện âm thanh bất thường vượt ngưỡng an toàn.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isResolved ? const Color(0xFF1E293B) : const Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!isResolved) ...[
                      const Divider(height: 16, color: Color(0xFFFCA5A5)),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Nút 1: Xem Vị Trí Con
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D9488),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.my_location, size: 15),
                            label: const Text('Xem Vị Trí Con', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              setState(() {
                                alert['isResolved'] = true;
                              });
                              _service.resolveAlert(alert['id']);
                              final childLoc = _locations.firstWhere(
                                (l) => l['username'] == alert['username'],
                                orElse: () => {
                                  'username': alert['username'] ?? 'duc',
                                  'latitude': 10.846939,
                                  'longitude': 106.775958,
                                  'addressName': 'Khu Công Nghệ Cao, TP. Thủ Đức, TP.HCM',
                                },
                              );
                              _showMemberLocationDetail(childLoc);
                            },
                          ),

                          // Nút 2: Đã xem thông báo (Khóa máy đã chuyển sang Tab riêng 2. Khóa Máy Con)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.done_all, size: 15),
                            label: const Text('Đã Kiểm Tra', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              setState(() {
                                alert['isResolved'] = true;
                              });
                              _service.resolveAlert(alert['id']);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],

          // Thẻ GPS của Chủ gia đình
          Card(
            color: const Color(0xFFF0FDF4),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFBBF7D0), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.my_location, color: Color(0xFF16A34A)),
                      SizedBox(width: 8),
                      Text('Vị Trí Của Bạn (Chủ Gia Đình - GPS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF166534))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentGpsText,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF15803D)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📍 $_currentAddressText',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isGettingLocation
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.share_location, size: 18),
                    label: Text(_isGettingLocation ? 'Đang lấy tọa độ chuẩn...' : 'Cập Nhật & Chia Sẻ Vị Trí Ngay'),
                    onPressed: _isGettingLocation ? null : _shareMyLocation,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bản Đồ VietMap Giám Sát Con Yêu (Live 24/7)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '👉 Nhấn vào thành viên để xem bản đồ chi tiết, tọa độ GPS & dẫn đường',
                      style: TextStyle(fontSize: 11, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.radar, size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 4),
                    Text('RADAR LIVE', style: TextStyle(color: Color(0xFF166534), fontSize: 10, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preview bản đồ VietMap nhanh của con yêu nếu có
          if (_locations.any((l) => l['username'] != widget.username)) ...[
            Builder(builder: (ctx) {
              final child = _locations.firstWhere((l) => l['username'] != widget.username);
              final cLat = (child['latitude'] is num) ? (child['latitude'] as num).toDouble() : 10.846939;
              final cLng = (child['longitude'] is num) ? (child['longitude'] as num).toDouble() : 106.775958;
              final cName = child['username'] ?? 'Con yêu';
              final cAddress = child['addressName'] ?? 'Khu Công Nghệ Cao, TP. Thủ Đức';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: VietmapViewerWidget(
                  latitude: cLat,
                  longitude: cLng,
                  title: 'Vị trí con yêu: $cName',
                  address: cAddress,
                  height: 180,
                  showControls: false,
                  onFullScreen: () => _showMemberLocationDetail(child),
                ),
              );
            }),
          ],

          _buildFamilyMembersListWidget(isOwnerView: true, isLocationTab: true),
        ],
      ),
    );
  }

  // ==============================================================
  // A. VAI TRÒ CHỦ GIA ĐÌNH: 2. LÁ CHẮN TỰ ĐỘNG CHẶN TRUY CẬP & TẢI XUỐNG
  // Không cần phụ huynh phải gắn link vô kiểm tra thủ công!
  // ==============================================================
  Widget _buildOwnerWebFilterTab() {
    final webAlerts = _alerts.where((a) => a['alertType'] == 'WEB_BLOCKED' || a['alertType'] == 'AUTO_BLOCKED').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Lá chắn bảo vệ tự động
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '🛡️ Lá Chắn Tự Động Bảo Vệ Trẻ 24/7',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Hệ thống tự động giám sát ngầm: Khi con bạn truy cập web xấu hoặc bấm tải bất kỳ tệp độc hại nào (.apk lạ, .exe, mã độc, cờ bạc), hệ thống sẽ TỰ ĐỘNG CHẶN ĐỨNG NGAY LẬP TỨC và gửi thông báo về đây. Ba Mẹ KHÔNG CẦN phải tự dán link vào kiểm tra!',
                  style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Nhật Ký Tự Động Ngăn Chặn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
              Chip(
                backgroundColor: const Color(0xFFDCFCE7),
                side: const BorderSide(color: Color(0xFF86EFAC)),
                label: const Text('Tự động bảo vệ: BẬT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            webAlerts.isEmpty
                ? 'Hiện chưa ghi nhận hành vi truy cập hoặc tải tệp độc hại nào từ thiết bị con.'
                : 'Đã tự động ngăn chặn ${webAlerts.length} lần con cố truy cập/tải nội dung rủi ro:',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),

          if (webAlerts.isEmpty)
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.verified_user, color: Colors.green, size: 48),
                    SizedBox(height: 10),
                    Text('Thiết Bị Của Trẻ Đang An Toàn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 4),
                    Text(
                      'Hệ thống đang chạy ngầm bảo vệ. Bất kỳ tải xuống file lạ hoặc web độc hại nào sẽ bị tự động chặn ngay lập tức.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: webAlerts.length,
              itemBuilder: (ctx, i) {
                final a = webAlerts[i];
                final isResolved = a['isResolved'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  color: isResolved ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isResolved ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isResolved ? Icons.check_circle : Icons.gpp_bad, color: isResolved ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Thiết bị con: ${a['username'] ?? "Trẻ em"}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isResolved ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isResolved ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isResolved ? 'ĐÃ KIỂM TRA' : 'CẦN XỬ LÝ',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a['message'] ?? 'Đã tự động ngăn chặn truy cập tệp nguy hiểm.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isResolved ? const Color(0xFF1E293B) : const Color(0xFF7F1D1D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: !isResolved
                              ? ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline, size: 16),
                                  label: const Text('Đã liên hệ kiểm tra an toàn'),
                                  onPressed: () async {
                                    setState(() {
                                      a['isResolved'] = true;
                                    });
                                    await _service.resolveAlert(a['id']);
                                    _loadAllData();
                                  },
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified, size: 16, color: Color(0xFF16A34A)),
                                      SizedBox(width: 6),
                                      Text(
                                        'Đã kiểm tra an toàn cho con',
                                        style: TextStyle(
                                          color: Color(0xFF15803D),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 16),
          const Text('Các Tiêu Chuẩn Tự Động Chặn Ngầm 24/7', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          _buildRuleItem('Tự động chặn Tải tệp không rõ nguồn gốc', 'Chặn ngay khi trẻ bấm tải file .apk, .exe, file hack, mod game lạ', true),
          _buildRuleItem('Tự động chặn Trang web Cờ bạc / Cá độ', 'Chặn ngay lập tức khi phát hiện từ khóa casino, bài bạc, bet, tài xỉu', true),
          _buildRuleItem('Tự động chặn Nội dung 18+ & Độc hại', 'Chặn tức thì các liên kết người lớn, bạo lực không phù hợp lứa tuổi', true),
          _buildRuleItem('Tự động chặn Tên miền lừa đảo rủi ro cao', 'Tự động khóa tên miền đuôi .xyz, .tk, .top, .vip, lừa nạp thẻ game', true),
        ],
      ),
    );
  }

  Widget _buildRuleItem(String title, String desc, bool isEnabled) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.verified, color: isEnabled ? Colors.green : Colors.grey),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        trailing: Switch(value: isEnabled, activeThumbColor: AppTheme.primary, onChanged: (_) {}),
      ),
    );
  }

  Widget _buildAutoBlockActionTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: iconColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: iconColor.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // MÀN HÌNH KHÓA MÁY TRẺ EM (CHILD DEVICE LOCKED FULLSCREEN OVERLAY)
  // Khi phụ huynh kích hoạt Khóa máy từ xa -> Màn hình này bao phủ toàn bộ app
  // Không cho phép thoát, chỉ cho phép Gọi điện khẩn cấp hoặc Xin mở khóa
  // ==============================================================
  Widget _buildChildLockedScreen({bool isTestMode = false, bool isPreview = false}) {
    return PopScope(
      canPop: isTestMode || isPreview,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark slate
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPreview) ...[
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        tooltip: 'Đóng bản xem trước',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (isTestMode) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.science, color: Color(0xFF38BDF8), size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '🧪 THỬ NGHIỆM MÀN HÌNH KHÓA\n(Nhập PIN 8888 hoặc bấm Thoát)',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              setState(() => _isTestLockActive = false);
                            },
                            child: const Text('Thoát', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Icon khóa to nổi bật với vòng hiệu ứng cảnh báo
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                      border: Border.all(color: const Color(0xFFDC2626), width: 3),
                    ),
                    child: const Center(
                      child: Icon(Icons.phonelink_lock, size: 48, color: Color(0xFFEF4444)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Tiêu đề cảnh báo
                  const Text(
                    'THIẾT BỊ ĐÃ BỊ TẠM KHÓA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Khung hiển thị lý do khóa từ ba mẹ (Nổi bật, rõ ràng)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF991B1B).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFFFCA5A5), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'LÝ DO KHÓA MÁY TỪ BA MẸ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFCA5A5),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _childLockReason.isNotEmpty ? _childLockReason : 'Đến giờ học bài tập trung / nghỉ ngơi',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Khung thông điệp an toàn
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: const Text(
                      'Các ứng dụng và chức năng giải trí tạm thời bị tạm dừng để nhắc nhở an toàn hoặc trong khung giờ quy định.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Trạng thái kiểm tra ngầm thời gian thực
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Tự động mở khóa ngay khi Ba Mẹ gỡ lệnh...',
                        style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                                    // Nút Gọi Khẩn Cấp Cho Ba Mẹ
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.phone_in_talk, size: 20),
                      label: const Text(
                        '📞 Gọi Khẩn Cấp Cho Ba Mẹ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _showEmergencyCallDialog,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nút Gửi Yêu Cầu Xin Mở Khóa
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.mail_outline, size: 20),
                      label: const Text(
                        'Gửi Yêu Cầu Xin Mở Khóa Đến Ba Mẹ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _showRequestUnlockDialog,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nút Mở Khóa Bằng Mã PIN Ba Mẹ (TUYỆT ĐỐI KHÔNG gợi ý mã PIN, KHÔNG có nút Mở Khóa Luôn)
                  Center(
                    child: TextButton.icon(
                      onPressed: _showParentPinUnlockDialog,
                      icon: const Icon(Icons.vpn_key, color: Colors.white70, size: 16),
                      label: const Text(
                        '🔐 Mở khóa bằng mã PIN Ba Mẹ',
                        style: TextStyle(color: Colors.white70, fontSize: 13, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showParentPinUnlockDialog() {
    final pinCtrl = TextEditingController();
    bool isVerifying = false;
    String? pinError;
    Timer? pinErrorTimer;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.vpn_key, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Text('Mở Khóa Bằng Mã PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập mã PIN do Ba Mẹ đã cài đặt để mở khóa thiết bị ngay tại chỗ:',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                onChanged: (_) {
                  if (pinError != null) {
                    setDialogState(() => pinError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Nhập mã PIN Ba Mẹ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.password),
                ),
              ),
              if (pinError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pinError!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying
                  ? null
                  : () {
                      pinErrorTimer?.cancel();
                      Navigator.pop(ctx);
                    },
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isVerifying
                  ? null
                  : () async {
                      final pin = pinCtrl.text.trim();
                      if (pin.isEmpty) {
                        setDialogState(() {
                          pinError = 'Vui lòng nhập mã PIN!';
                        });
                        pinErrorTimer?.cancel();
                        pinErrorTimer = Timer(const Duration(seconds: 5), () {
                          if (ctx.mounted) {
                            setDialogState(() => pinError = null);
                          }
                        });
                        return;
                      }

                      setDialogState(() {
                        isVerifying = true;
                        pinError = null;
                      });
                      final res = await _service.verifyUnlockPin(
                        childUsername: widget.username,
                        pin: pin,
                      );

                      if (!mounted) return;

                      if (res['verified'] == true) {
                        pinErrorTimer?.cancel();
                        if (ctx.mounted) Navigator.pop(ctx);
                        setState(() {
                          _isChildDeviceLocked = false;
                          _isTestLockActive = false;
                          _childLockReason = '';
                        });
                        await _service.setChildLock(childUsername: widget.username, isLocked: false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔓 Đã xác thực mã PIN Ba Mẹ và mở khóa điện thoại thành công!'),
                              backgroundColor: Color(0xFF16A34A),
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      } else {
                        final errMsg = res['message'] ?? '❌ Mã PIN Ba Mẹ không chính xác!';
                        setDialogState(() {
                          isVerifying = false;
                          pinError = errMsg;
                        });
                        pinErrorTimer?.cancel();
                        pinErrorTimer = Timer(const Duration(seconds: 5), () {
                          if (ctx.mounted) {
                            setDialogState(() => pinError = null);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          }
                        });

                        if (mounted) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errMsg),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
              child: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Mở Khóa'),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  void _showEmergencyCallDialog() {
    final ownerMember = _members.firstWhere(
      (m) =>
          (m['role']?.toString().toLowerCase() == 'owner' || m['username'] == 'duc') &&
          (m['phoneNumber']?.toString().isNotEmpty ?? false),
      orElse: () => {'phoneNumber': '0978282049', 'username': 'Ba Mẹ (Đức)'},
    );
    final phone = ownerMember['phoneNumber']?.toString() ?? '0978282049';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEF4444)),
        ),
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 8),
            Text('Cuộc Gọi Khẩn Cấp', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trong tình huống cần thiết, con có thể gọi điện trực tiếp cho Ba Mẹ hoặc tổng đài khẩn cấp ngay tại đây:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF22C55E)),
              ),
              leading: const CircleAvatar(backgroundColor: Color(0xFF16A34A), child: Icon(Icons.call, color: Colors.white)),
              title: const Text('Gọi Điện Cho Ba Mẹ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(phone, style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12)),
              onTap: () async {
                final uri = Uri.parse('tel:$phone');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Số điện thoại Ba Mẹ: $phone')));
                }
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              tileColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFEF4444)),
              ),
              leading: const CircleAvatar(backgroundColor: Color(0xFFDC2626), child: Icon(Icons.emergency, color: Colors.white)),
              title: const Text('Gọi Cảnh Sát Khẩn Cấp (113)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Tổng đài hỗ trợ khẩn cấp', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
              onTap: () async {
                final uri = Uri.parse('tel:113');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  // QUY TRÌNH THỎA THUẬN & BẮT BUỘC CẤP QUYỀN KIỂM SOÁT THIẾT BỊ
  // (MANDATORY DEVICE SUPERVISION & PARENTAL CONTROL CONSENT)
  // ==============================================================
  Future<void> _checkAndPromptSupervisionConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final consentGiven = prefs.getBool('device_supervision_consent_${widget.username}') ?? false;
      if (!consentGiven && mounted) {
        _showMandatorySupervisionModal();
      }
    } catch (_) {}
  }

  void _showMandatorySupervisionModal() {
    bool isAgreed = false;
    bool isDeviceAdminChecked = true;
    bool isUsageStatsChecked = true;
    bool isOverlayChecked = true;
    bool isGpsChecked = true;
    bool isNoiseChecked = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(Icons.shield, color: Color(0xFFDC2626), size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THỎA THUẬN KIỂM SOÁT THIẾT BỊ',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF991B1B)),
                      ),
                      Text(
                        'Bắt buộc đồng ý để sử dụng ứng dụng',
                        style: TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        '📢 Để kích hoạt hệ thống bảo vệ an toàn gia đình, bạn bắt buộc phải cấp quyền kiểm soát điện thoại cho Ba Mẹ. Ứng dụng sẽ giám sát các hoạt động, phát hiện nguy cơ và khóa máy từ xa khi nhận lệnh từ Ba Mẹ.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'CÁC QUYỀN KIỂM SOÁT THIẾT BỊ BẮT BUỘC:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),

                    _buildPermissionItem(
                      icon: Icons.admin_panel_settings,
                      iconColor: const Color(0xFFDC2626),
                      title: '1. Quyền Quản Trị Viên (Device Admin)',
                      desc: 'Cho phép Ba Mẹ gửi lệnh KHÓA MÁY từ xa khi vi phạm hoặc đến giờ học. Ngăn trẻ tự ý gỡ ứng dụng.',
                      isChecked: isDeviceAdminChecked,
                    ),
                    _buildPermissionItem(
                      icon: Icons.remove_red_eye,
                      iconColor: const Color(0xFFEA580C),
                      title: '2. Giám Sát Hoạt Động & Ứng Dụng (Usage Stats)',
                      desc: 'Tự động kiểm tra ứng dụng đang mở, thời lượng dùng máy và tệp tải lạ để gửi cảnh báo về Ba Mẹ.',
                      isChecked: isUsageStatsChecked,
                    ),
                    _buildPermissionItem(
                      icon: Icons.layers,
                      iconColor: const Color(0xFF7C3AED),
                      title: '3. Hiển Thị Đè Màn Hình (Draw Over Apps)',
                      desc: 'Hiển thị màn hình khóa cưỡng chế ngay lập tức khi nhận lệnh khóa từ Ba Mẹ hoặc đến giờ học.',
                      isChecked: isOverlayChecked,
                    ),
                    _buildPermissionItem(
                      icon: Icons.location_on,
                      iconColor: const Color(0xFF0284C7),
                      title: '4. Định Vị Vệ Tinh 24/7 (Background GPS)',
                      desc: 'Truyền tọa độ liên tục mỗi 8 giây để phụ huynh thấy vị trí con di chuyển mà không cần con bấm gửi.',
                      isChecked: isGpsChecked,
                    ),
                    _buildPermissionItem(
                      icon: Icons.mic,
                      iconColor: const Color(0xFF0F766E),
                      title: '5. Cảm Biến Âm Thanh Nhạy Bén (24/7 Audio)',
                      desc: 'Tự động phát hiện âm thanh bất thường (va chạm lớn, tiếng la hét) để phát cảnh báo SOS về Ba Mẹ.',
                      isChecked: isNoiseChecked,
                    ),

                    const SizedBox(height: 12),
                    // Checkbox xác nhận
                    InkWell(
                      onTap: () => setModalState(() => isAgreed = !isAgreed),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isAgreed ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isAgreed ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isAgreed,
                              activeColor: const Color(0xFF16A34A),
                              onChanged: (v) => setModalState(() => isAgreed = v ?? false),
                            ),
                            const Expanded(
                              child: Text(
                                'Tôi đã đọc, hiểu rõ và HOÀN TOÀN ĐỒNG Ý cấp toàn bộ quyền kiểm soát thiết bị này cho Ba Mẹ.',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAgreed ? const Color(0xFF16A34A) : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text(
                    'ĐỒNG Ý CẤP QUYỀN & TIẾP TỤC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: !isAgreed
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('device_supervision_agreed_${widget.username}', true);
                          await _service.grantSupervision(childUsername: widget.username);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Đã kích hoạt chế độ kiểm soát thiết bị & kết nối với Ba Mẹ thành công!'),
                                backgroundColor: Color(0xFF16A34A),
                              ),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required bool isChecked,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'BẮT BUỘC',
                        style: TextStyle(color: Color(0xFF166534), fontSize: 9, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _promptLockChildDevice(String childName) {
    String selectedReason = 'Đến giờ học bài tập trung';
    final customCtrl = TextEditingController();
    final pinCtrl = TextEditingController(text: '8888');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phonelink_lock, color: Color(0xFFDC2626), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Khóa Máy: $childName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF991B1B))),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chọn lý do khóa màn hình điện thoại của con từ xa:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              ...[
                'Đến giờ học bài tập trung',
                'Đến giờ đi ngủ',
                'Hết thời gian dùng máy trong ngày',
                'Nhắc nhở vi phạm quy định',
                'Khác (nhập tự do)'
              ].map((r) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r, style: const TextStyle(fontSize: 12)),
                    value: r,
                    groupValue: selectedReason,
                    onChanged: (v) => setModalState(() => selectedReason = v ?? selectedReason),
                  )),
              if (selectedReason == 'Khác (nhập tự do)') ...[
                const SizedBox(height: 6),
                TextField(
                  controller: customCtrl,
                  decoration: InputDecoration(
                    hintText: 'Nhập lý do gửi đến con...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.pin, size: 16, color: Color(0xFF0F172A)),
                  SizedBox(width: 6),
                  Text(
                    'Cài đặt mã PIN mở khóa khẩn cấp:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Mã PIN 4-6 số mở trực tiếp trên máy của con (giữ bí mật, màn hình con không gợi ý mã này):',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'Nhập mã PIN (Mặc định: 8888)',
                  prefixIcon: const Icon(Icons.password, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final finalReason = selectedReason == 'Khác (nhập tự do)' && customCtrl.text.trim().isNotEmpty
                    ? customCtrl.text.trim()
                    : selectedReason;
                final finalPin = pinCtrl.text.trim().isEmpty ? '8888' : pinCtrl.text.trim();
                final targetUser = (childName == 'Tất cả thiết bị con' || childName == 'all') ? 'all' : childName;
                setState(() {
                  if (targetUser == 'all') {
                    for (final m in _members) { m['isDeviceLocked'] = true; }
                    for (final l in _locations) { l['isDeviceLocked'] = true; }
                  } else {
                    for (final m in _members) {
                      if (m['username']?.toString().toLowerCase() == targetUser.toLowerCase()) {
                        m['isDeviceLocked'] = true;
                      }
                    }
                    for (final l in _locations) {
                      if (l['username']?.toString().toLowerCase() == targetUser.toLowerCase()) {
                        l['isDeviceLocked'] = true;
                      }
                    }
                  }
                });

                final res = await _service.setChildLock(
                  childUsername: targetUser,
                  isLocked: true,
                  reason: finalReason,
                  unlockPin: finalPin,
                );
                if (!isOwner && (targetUser.toLowerCase() == widget.username.toLowerCase() || targetUser == 'all')) {
                  setState(() {
                    _isChildDeviceLocked = true;
                    _childLockReason = finalReason;
                  });
                }
                await _loadAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? '🔒 Đã phát lệnh KHÓA MÁY thành công đến thiết bị của $childName!'),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              },
              child: const Text('Phát Lệnh Khóa Ngay'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRequestUnlockDialog() {
    final reasonCtrl = TextEditingController(text: 'Con cần dùng máy để tra cứu học bài');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('Xin Mở Khóa Máy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập lý do gửi đến Ba Mẹ:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Nhập lý do xin mở khóa...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.sendSafetyAlert(
                username: widget.username,
                alertType: 'UNLOCK_REQUEST',
                message: 'Bé ${widget.username} xin mở khóa máy: "${reasonCtrl.text.trim()}"',
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã gửi yêu cầu xin mở khóa đến máy Ba Mẹ!'),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: const Text('Gửi Ba Mẹ'),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // B. VAI TRÒ TRẺ EM: 1. LÁ CHẮN TỰ ĐỘNG BẢO VỆ CON 24/7
  // Tự động chặn ngay khi con truy cập hay tải bất kỳ nội dung xấu nào
  // Hoàn toàn không cần phụ huynh phải dán link vào kiểm tra thủ công!
  // ==============================================================
  Widget _buildChildWebShieldTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Lá Chắn Tự Động Thông Minh
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D9488), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🛡️ LÁ CHẮN BẢO VỆ TỰ ĐỘNG 24/7',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '🟢 Trạng thái: Đang bảo vệ ngầm theo thời gian thực',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '⚡ Hệ thống tự động nhận diện và CHẶN NGAY LẬP TỨC khi con bấm tải tệp lạ (.apk, .exe, hack mod) hoặc vào web cờ bạc, 18+, lừa đảo.\n✨ Ba Mẹ và Con KHÔNG CẦN phải dán link kiểm tra thủ công!',
                    style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Khung thử nghiệm phản ứng tự động chặn
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.flash_on, color: Color(0xFFDC2626), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Mô Phỏng Trực Quan Tự Động Chặn',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Bấm vào các tình huống dưới đây để xem Lá Chắn tự động phát hiện, chặn đứng tức thì và báo cho Ba Mẹ:',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 14),

                  // Nút 1: Tải APK lạ
                  _buildAutoBlockActionTile(
                    icon: Icons.file_download_off,
                    iconColor: const Color(0xFFDC2626),
                    bgColor: const Color(0xFFFEE2E2),
                    title: 'Tải file: FreeFire_Mod_BatTu.apk',
                    subtitle: 'Tệp APK mod không rõ nguồn gốc (Mã độc)',
                    badgeText: 'TỰ CHẶN TẢI',
                    badgeColor: const Color(0xFFDC2626),
                    onTap: () => _handleAutoBlockEvent(
                      targetName: 'FreeFire_Mod_BatTu.apk',
                      actionType: 'DOWNLOAD',
                      category: 'Tải tệp APK lạ / Mã độc',
                      reason: 'Phát hiện tệp APK từ nguồn không đáng tin cậy, nguy cơ chứa mã độc đánh cắp tài khoản.',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nút 2: Tải file EXE Trojan
                  _buildAutoBlockActionTile(
                    icon: Icons.warning_amber_rounded,
                    iconColor: const Color(0xFFEA580C),
                    bgColor: const Color(0xFFFFEDD5),
                    title: 'Tải phần mềm: HackRobux_Auto.exe',
                    subtitle: 'File thực thi nguy hiểm (.exe) chứa Trojan',
                    badgeText: 'TỰ CHẶN TẢI',
                    badgeColor: const Color(0xFFEA580C),
                    onTap: () => _handleAutoBlockEvent(
                      targetName: 'HackRobux_Auto.exe',
                      actionType: 'DOWNLOAD',
                      category: 'Phần mềm độc hại (.exe)',
                      reason: 'Tệp thực thi độc hại có nguy cơ chiếm quyền kiểm soát máy và đọc trộm tin nhắn.',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nút 3: Vào web cá độ
                  _buildAutoBlockActionTile(
                    icon: Icons.public_off,
                    iconColor: const Color(0xFFB91C1C),
                    bgColor: const Color(0xFFFEE2E2),
                    title: 'Vào web: Cobac_TaiXiu68.xyz',
                    subtitle: 'Trang cá cược cờ bạc bị cấm',
                    badgeText: 'TỰ CHẶN TRUY CẬP',
                    badgeColor: const Color(0xFFB91C1C),
                    onTap: () => _handleAutoBlockEvent(
                      targetName: 'Cobac_TaiXiu68.xyz',
                      actionType: 'ACCESS',
                      category: 'Cờ bạc & Cá độ online',
                      reason: 'Tên miền cờ bạc trực tuyến trái pháp luật nằm trong danh mục cấm quốc gia.',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nút 4: Vào web lừa đảo
                  _buildAutoBlockActionTile(
                    icon: Icons.phishing,
                    iconColor: const Color(0xFFC026D3),
                    bgColor: const Color(0xFFFAE8FF),
                    title: 'Vào web: Napthengay_FreeVip.top',
                    subtitle: 'Web giả mạo lừa đảo nạp thẻ game',
                    badgeText: 'TỰ CHẶN TRUY CẬP',
                    badgeColor: const Color(0xFFC026D3),
                    onTap: () => _handleAutoBlockEvent(
                      targetName: 'Napthengay_FreeVip.top',
                      actionType: 'ACCESS',
                      category: 'Trang web lừa đảo (Phishing)',
                      reason: 'Trang mạo danh nhằm chiếm đoạt mã thẻ cào và thông tin tài khoản cá nhân.',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nút 5: Tải tài liệu an toàn (Hợp lệ)
                  _buildAutoBlockActionTile(
                    icon: Icons.verified_user,
                    iconColor: const Color(0xFF16A34A),
                    bgColor: const Color(0xFFDCFCE7),
                    title: 'Tải tài liệu: DeThi_ToanLop5.pdf',
                    subtitle: 'Tài liệu học tập giáo dục chính quy',
                    badgeText: 'AN TOÀN - HỢP LỆ',
                    badgeColor: const Color(0xFF16A34A),
                    onTap: () => _handleAutoBlockEvent(
                      targetName: 'DeThi_ToanLop5.pdf',
                      actionType: 'DOWNLOAD',
                      category: 'Tài liệu học tập',
                      reason: '',
                      isAllowed: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Lịch sử duyệt web & tải tệp được bảo vệ
          const Text('Nhật Ký Bảo Vệ & Chặn Tự Động', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _childWebHistory.length,
            itemBuilder: (ctx, i) {
              final item = _childWebHistory[i];
              final isBlocked = item['isBlocked'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: isBlocked ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC), width: 1.2),
                ),
                color: isBlocked ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isBlocked ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                    child: Icon(isBlocked ? Icons.block : Icons.check, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    item['url'] ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isBlocked ? const Color(0xFF991B1B) : const Color(0xFF166534),
                    ),
                  ),
                  subtitle: Text(
                    isBlocked
                        ? '🚫 ĐÃ CHẶN TRUY CẬP (Đã gửi cảnh báo đến Ba Mẹ)\n⏱️ ${item['time']}'
                        : '✅ Trang web an toàn được phép sử dụng\n⏱️ ${item['time']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isBlocked ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // Lời khuyên an toàn số
          Card(
            color: const Color(0xFFEFF6FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 8),
                      Text('Lời Dặn Dành Riêng Cho Con', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('• Không nhấp vào đường link lạ mời nhận kim cương hay quà tặng game miễn phí.', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A))),
                  SizedBox(height: 4),
                  Text('• Không bao giờ nhập mật khẩu tài khoản lên bất kỳ trang web nào không rõ nguồn gốc.', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A))),
                  SizedBox(height: 4),
                  Text('• Khi điện thoại báo ĐÃ CHẶN TRUY CẬP, hãy trao đổi ngay với Ba Mẹ để được hỗ trợ nhé!', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // B. VAI TRÒ TRẺ EM: 2. HÒM THƯ & THÔNG BÁO TIN NHẮN TỪ GIA ĐÌNH
  // ==============================================================
  Widget _buildChildNotificationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            color: Colors.white,
            elevation: 1,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(Icons.notifications_active, color: Color(0xFF0284C7), size: 26),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hòm Thư Tin Nhắn Gia Đình', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 4),
                        Text('Lời nhắc nhở, dặn dò và các thông báo phê duyệt từ Ba Mẹ.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text('Tin Nhắn & Thông Báo Mới Nhất', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),

          _buildMessageCard(
            sender: 'Ba Mẹ (Chủ Gia Đình)',
            role: 'Phụ huynh',
            time: '10 phút trước',
            content: 'Con nhớ chỉ vào các trang web học tập và giải trí đã được gia đình duyệt nhé. Tuyệt đối không nhấp link lạ nha con!',
            isUrgent: false,
            badgeColor: const Color(0xFF8B5CF6),
          ),

          _buildMessageCard(
            sender: 'Hệ Thống Bảo Vệ Gia Đình',
            role: 'Hệ thống tự động',
            time: '35 phút trước',
            content: 'Tính năng Giám Sát Web Độc Hại đã được bật. Mọi đường link lạ không an toàn sẽ tự động bị chặn để bảo vệ bạn.',
            isUrgent: false,
            badgeColor: const Color(0xFF10B981),
          ),

          if (_childRequests.isNotEmpty)
            ..._childRequests.map((r) => _buildMessageCard(
                  sender: 'Kết Quả Xin Thêm Giờ',
                  role: 'Hệ thống',
                  time: 'Hôm nay',
                  content: 'Yêu cầu xin thêm ${r['extraMinutes']} phút sử dụng máy của bạn: ${r['status'] == 'APPROVED' ? 'ĐÃ ĐƯỢC BA MẸ DUYỆT ✅' : (r['status'] == 'REJECTED' ? 'BA MẸ ĐÃ TỪ CHỐI ❌' : 'ĐANG CHỜ BA MẸ PHÊ DUYỆT ⏳')}',
                  isUrgent: false,
                  badgeColor: r['status'] == 'APPROVED' ? Colors.green : (r['status'] == 'REJECTED' ? Colors.red : Colors.orange),
                )),

          _buildMessageCard(
            sender: 'Cảnh Báo Chặn Web',
            role: 'Cảnh báo an toàn',
            time: 'Hôm qua',
            content: 'Điện thoại của bạn đã chặn 1 trang web lạ nghi ngờ lừa đảo. Báo cáo chi tiết đã được gửi tới máy của Ba Mẹ.',
            isUrgent: true,
            badgeColor: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({
    required String sender,
    required String role,
    required String time,
    required String content,
    required bool isUrgent,
    required Color badgeColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isUrgent ? Colors.redAccent : Colors.grey.shade200, width: isUrgent ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: badgeColor.withValues(alpha: 0.15),
                  child: Icon(Icons.person, size: 16, color: badgeColor),
                ),
                const SizedBox(width: 8),
                Text(sender, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Text(time, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // B. VAI TRÒ TRẺ EM: 3. VỊ TRÍ CỦA CON & SOS CỨU HỘ
  // (TUYỆT ĐỐI KHÔNG CÓ DANH SÁCH VỊ TRÍ CỦA THÀNH VIÊN KHÁC)
  // ==============================================================
  Widget _buildChildMyGpsAndSosTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nút SOS cứu hộ khẩn cấp
          GestureDetector(
            onTap: _triggerSos,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Icon(Icons.touch_app, size: 54, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    'SOS KHẨN CẤP',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Chạm ngay để gửi tín hiệu cầu cứu & vị trí đến Ba Mẹ',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Thẻ GPS Định Vị Tự Động Liên Tục 24/7 (Con không cần bấm gửi)
          Card(
            color: const Color(0xFFF0FDF4),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF86EFAC), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDCFCE7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.satellite_alt, color: Color(0xFF16A34A), size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Định Vị Tự Động Liên Tục 24/7',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF166534)),
                            ),
                            Text(
                              '🟢 Ba Mẹ thấy trực tiếp, con không cần bấm gửi',
                              style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('LIVE GPS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.place, color: Color(0xFF16A34A), size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _currentAddressText,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.gps_fixed, color: AppTheme.textSecondary, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Tọa độ: $_currentGpsText',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.sync, color: Color(0xFF10B981), size: 14),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Đồng bộ ngầm tự động mỗi 8 giây về điện thoại Ba Mẹ',
                                style: TextStyle(fontSize: 10, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bản đồ VietMap vị trí hiện tại của con
                  VietmapViewerWidget(
                    latitude: _currentLat,
                    longitude: _currentLng,
                    title: 'Vị trí của bạn',
                    address: _currentAddressText,
                    height: 200,
                    showControls: true,
                  ),
                  const SizedBox(height: 14),
                  const Text('Mô Phỏng Di Chuyển Để Ba Mẹ Thấy Trực Tiếp:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.school, size: 16, color: Colors.blueAccent),
                        label: const Text('Đang ở Trường Học', style: TextStyle(fontSize: 11)),
                        backgroundColor: const Color(0xFFE0F2FE),
                        onPressed: () {
                          _autoSendChildLocationSilently(
                            overrideLat: 10.8505,
                            overrideLng: 106.7720,
                            overrideAddress: 'Trường Tiểu Học Tân Phú, TP. Thủ Đức, TP.HCM',
                            speed: 0.0,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('📍 Đã tự động cập nhật vị trí con đang ở Trường Học đến Ba Mẹ!'),
                              backgroundColor: Color(0xFF0284C7),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.directions_bike, size: 16, color: Colors.orange),
                        label: const Text('Đang về nhà (16 km/h)', style: TextStyle(fontSize: 11)),
                        backgroundColor: const Color(0xFFFFEDD5),
                        onPressed: () {
                          _autoSendChildLocationSilently(
                            overrideLat: 10.8420,
                            overrideLng: 106.7780,
                            overrideAddress: 'Đang di chuyển trên đường Lê Văn Việt, TP. Thủ Đức',
                            speed: 16.5,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🚲 Đã tự động phát vị trí con đang di chuyển (16.5 km/h) đến Ba Mẹ!'),
                              backgroundColor: Color(0xFFEA580C),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.home, size: 16, color: Colors.green),
                        label: const Text('Đang ở Nhà an toàn', style: TextStyle(fontSize: 11)),
                        backgroundColor: const Color(0xFFDCFCE7),
                        onPressed: () {
                          _autoSendChildLocationSilently(
                            overrideLat: 10.846939,
                            overrideLng: 106.775958,
                            overrideAddress: 'Khu Công Nghệ Cao (Nhà An Toàn), TP. Thủ Đức',
                            speed: 0.0,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🏠 Đã tự động đồng bộ vị trí con đang ở Nhà an toàn đến Ba Mẹ!'),
                              backgroundColor: Color(0xFF16A34A),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Khung Điều Khiển Trực Tiếp Khóa Màn Hình & Trải Nghiệm Mở Khóa
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _isChildDeviceLocked ? const Color(0xFFFCA5A5) : const Color(0xFFCBD5E1)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phonelink_lock, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kiểm Soát Màn Hình & Khóa Máy Từ Xa:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isChildDeviceLocked ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isChildDeviceLocked ? '🔴 BỊ KHÓA' : '🟢 BÌNH THƯỜNG',
                        style: TextStyle(
                          color: _isChildDeviceLocked ? const Color(0xFF991B1B) : const Color(0xFF166534),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Khi Ba Mẹ phát lệnh khóa từ xa, màn hình máy này sẽ lập tức kích hoạt khóa bảo vệ (chỉ gọi được số khẩn cấp hoặc mở bằng mã PIN Ba Mẹ đã cài đặt).',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isChildDeviceLocked ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: Icon(_isChildDeviceLocked ? Icons.lock_open : Icons.phonelink_lock, size: 16),
                    label: Text(
                      _isChildDeviceLocked ? 'Mở Khóa Máy Ngay' : '🔒 Khóa Thử Nghiệm Màn Hình Này Ngay',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: () {
                      setState(() => _isTestLockActive = true);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cảm Biến Đo Tiếng Ồn & AI Phân Tích Sự Cố Google YAMNet 24/7
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: _lastYamnetResult.isCritical
                    ? const Color(0xFFDC2626)
                    : (_lastYamnetResult.isWarning ? const Color(0xFFEA580C) : const Color(0xFF0D9488)),
                width: 2.0,
              ),
            ),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TIÊU ĐỀ & HUY HIỆU AI YAMNET
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _lastYamnetResult.isCritical
                                ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
                                : [const Color(0xFF0D9488), const Color(0xFF14B8A6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.psychology,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'AI YAMNet Đo Tiếng Ồn & Sự Cố',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 5),
                                const Expanded(
                                  child: Text(
                                    'Google AudioSet On-Device AI 24/7',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Text('AI ACTIVE', style: TextStyle(color: Color(0xFF166534), fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // MÔ TẢ HỆ THỐNG YAMNET
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCCFBF1)),
                    ),
                    child: const Text(
                      '🧠 Mô hình AI Google YAMNet (huấn luyện trên 521 phân lớp AudioSet) tự động phân tích phổ âm thanh thời gian thực để nhận diện chuẩn xác: Tiếng la hét, khóc lóc, va đập xe, ngã mạnh, quát tháo hay kính vỡ. Khi có nguy hiểm, hệ thống tự động kích hoạt gửi cảnh báo và vị trí GPS về cho Ba Mẹ!',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF115E59), height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // KHUNG TRẠNG THÁI NHẬN DIỆN THỜI GIAN THỰC CỦA YAMNET
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lastYamnetResult.isCritical
                          ? const Color(0xFFFEF2F2)
                          : (_lastYamnetResult.isWarning ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _lastYamnetResult.isCritical
                            ? const Color(0xFFFCA5A5)
                            : (_lastYamnetResult.isWarning ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0)),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _lastYamnetResult.isCritical
                                  ? Icons.warning_amber_rounded
                                  : (_lastYamnetResult.isWarning ? Icons.info_outline : Icons.check_circle_outline),
                              size: 18,
                              color: _lastYamnetResult.isCritical
                                  ? const Color(0xFFDC2626)
                                  : (_lastYamnetResult.isWarning ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Kết quả nhận diện AI YAMNet:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _lastYamnetResult.isCritical
                                    ? const Color(0xFFDC2626)
                                    : (_lastYamnetResult.isWarning ? const Color(0xFFEA580C) : const Color(0xFF16A34A)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(_lastYamnetResult.confidence * 100).toInt()}% Tin cậy',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _lastYamnetResult.labelVi,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _lastYamnetResult.isCritical
                                ? const Color(0xFF991B1B)
                                : (_lastYamnetResult.isWarning ? const Color(0xFFB45309) : const Color(0xFF15803D)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã phân loại: ${_lastYamnetResult.yamnetClass}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lastYamnetResult.adviceVi,
                          style: TextStyle(
                            fontSize: 11,
                            color: _lastYamnetResult.isCritical
                                ? const Color(0xFFDC2626)
                                : (_lastYamnetResult.isWarning ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // HIỂN THỊ ĐỒNG HỒ DECIBEL & VISUALIZER SÓNG ÂM
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        // Nút Bật/Tắt Microphone Thực Tế
                        InkWell(
                          onTap: () async {
                            final ok = await NoiseMeterService.instance.startListening(sensitivity: _noiseSensitivity);
                            if (mounted) {
                              setState(() => _isRealMicActive = ok);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '🎙️ Đã kết nối Micro thiết bị! Hệ thống AI YAMNet đang lắng nghe trực tiếp.'
                                      : '⚠️ Không thể mở Micro (vui lòng kiểm tra quyền truy cập).'),
                                  backgroundColor: ok ? AppTheme.success : Colors.orange,
                                ),
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: _isRealMicActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _isRealMicActive ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isRealMicActive ? Icons.mic : Icons.mic_off,
                                  color: _isRealMicActive ? const Color(0xFF16A34A) : const Color(0xFFB45309),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _isRealMicActive
                                        ? 'Micro Thực Tế: ĐANG ĐO & PHÂN TÍCH AI TRỰC TIẾP'
                                        : 'Bấm để BẬT MICROPHONE THỰC TẾ',
                                    style: TextStyle(
                                      color: _isRealMicActive ? const Color(0xFF166534) : const Color(0xFF92400E),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _isRealMicActive ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _isRealMicActive ? 'LIVE' : 'BẬT MIC',
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Chỉ số Decibel số lớn
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _currentDecibel.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: _lastYamnetResult.isCritical
                                    ? const Color(0xFFDC2626)
                                    : (_lastYamnetResult.isWarning ? const Color(0xFFEA580C) : const Color(0xFF0F766E)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'dB SPL',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Phổ sóng âm thanh 14 thanh nhảy liên tục
                        Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _audioWaveform.map((val) {
                              final ratio = (val / 100.0).clamp(0.12, 1.0);
                              Color barColor = _lastYamnetResult.isCritical
                                  ? const Color(0xFFDC2626)
                                  : (_lastYamnetResult.isWarning ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                width: 7,
                                height: (32 * ratio).toDouble(),
                                decoration: BoxDecoration(
                                  color: barColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 6),

                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (_currentDecibel / 110).clamp(0.0, 1.0),
                            minHeight: 7,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _lastYamnetResult.isCritical
                                  ? const Color(0xFFDC2626)
                                  : (_lastYamnetResult.isWarning ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // BỘ THỬ NGHIỆM MÔ PHỎNG CÁC PHÂN LỚP SỰ CỐ YAMNET (AUDIOSET SUITE)
                  const Row(
                    children: [
                      Icon(Icons.science, color: Color(0xFF7C3AED), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Thử Nghiệm Phân Lớp YAMNet Cứu Nạn:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 1. Screaming (La hét cầu cứu)
                  _buildAutoBlockActionTile(
                    icon: Icons.record_voice_over,
                    iconColor: const Color(0xFFDC2626),
                    bgColor: const Color(0xFFFEE2E2),
                    title: '1. Tiếng La Hét / Kêu Cứu (Screaming - /m/03qc9r)',
                    subtitle: 'Âm thanh tần số cao 1.5-3.5 kHz -> YAMNet: 95% độ tin cậy -> Tự động báo Ba Mẹ',
                    badgeText: 'LA HÉT 95%',
                    badgeColor: const Color(0xFFDC2626),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.screaming);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 2. Vehicle Crash / Impact (Va chạm xe / ngã mạnh)
                  _buildAutoBlockActionTile(
                    icon: Icons.car_crash,
                    iconColor: const Color(0xFFB91C1C),
                    bgColor: const Color(0xFFFEE2E2),
                    title: '2. Va Chạm Xe / Tai Nạn Ngã (Crash - /m/07r04)',
                    subtitle: 'Xung âm thanh va đập cực mạnh (93.8 dB) -> YAMNet: 97% -> Báo động tai nạn ngay',
                    badgeText: 'TAI NẠN 97%',
                    badgeColor: const Color(0xFFB91C1C),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.vehicleCrash);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 3. Crying / Sobbing (Khóc lóc, nức nở)
                  _buildAutoBlockActionTile(
                    icon: Icons.sentiment_very_dissatisfied,
                    iconColor: const Color(0xFFD97706),
                    bgColor: const Color(0xFFFEF3C7),
                    title: '3. Tiếng Khóc Lóc / Nức Nở (Crying - /m/07p6fty)',
                    subtitle: 'Nhịp rung tần số âm thanh ngắt quãng -> YAMNet: 89% -> Cảnh báo con hoảng loạn',
                    badgeText: 'KHÓC LÓC 89%',
                    badgeColor: const Color(0xFFD97706),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.crying);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 4. Shout / Yell (Quát tháo, bạo lực học đường)
                  _buildAutoBlockActionTile(
                    icon: Icons.campaign,
                    iconColor: const Color(0xFFEA580C),
                    bgColor: const Color(0xFFFFEDD5),
                    title: '4. Quát Tháo / Bạo Lực Học Đường (Shout - /m/07plz5l)',
                    subtitle: 'Năng lượng âm trung lớn kéo dài -> YAMNet: 88% -> Cảnh báo môi trường tranh cãi',
                    badgeText: 'QUÁT THÁO 88%',
                    badgeColor: const Color(0xFFEA580C),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.shout);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 5. Glass Breaking (Kính vỡ, đập phá)
                  _buildAutoBlockActionTile(
                    icon: Icons.broken_image,
                    iconColor: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFFF3E8FF),
                    title: '5. Kính Vỡ / Đập Phá (Glass Breaking - /m/07rwj37)',
                    subtitle: 'Đỉnh năng lượng tần số cực cao (>4kHz) -> YAMNet: 92% -> Cảnh báo đồ đạc đổ vỡ',
                    badgeText: 'KÍNH VỠ 92%',
                    badgeColor: const Color(0xFF7C3AED),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.glassBreaking);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 6. Groan / Whimper (Rên rỉ đau đớn)
                  _buildAutoBlockActionTile(
                    icon: Icons.healing,
                    iconColor: const Color(0xFF0284C7),
                    bgColor: const Color(0xFFE0F2FE),
                    title: '6. Rên Rỉ / Đau Đớn Bị Thương (Groan - /m/07s04w)',
                    subtitle: 'Âm thanh suy yếu kéo dài -> YAMNet: 82% -> Nghi ngờ chấn thương hoặc té ngã',
                    badgeText: 'RÊN RỈ 82%',
                    badgeColor: const Color(0xFF0284C7),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.groanWhimper);
                      setState(() => _lastYamnetResult = sim);
                      _triggerAutoNoiseAlert(
                        db: sim.decibel,
                        incidentType: 'AI YAMNet: ${sim.labelVi} (${(sim.confidence * 100).toInt()}%)',
                        isManualSimulation: true,
                        yamnetResult: sim,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // 7. Normal Ambient (Bình thường / An toàn)
                  _buildAutoBlockActionTile(
                    icon: Icons.volume_down,
                    iconColor: const Color(0xFF16A34A),
                    bgColor: const Color(0xFFDCFCE7),
                    title: '7. Môi Trường An Toàn / Bình Thường (Normal Ambient)',
                    subtitle: 'Mức âm thanh 42.0 dB an toàn -> AI YAMNet xác nhận trạng thái bình yên',
                    badgeText: 'AN TOÀN 99%',
                    badgeColor: const Color(0xFF16A34A),
                    onTap: () {
                      final sim = YamnetAudioSafetyService.instance.getSimulatedResult(YamnetSafetyCategory.safeNormal);
                      setState(() {
                        _currentDecibel = 42.0;
                        _lastYamnetResult = sim;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ AI YAMNet xác nhận môi trường an toàn (42.0 dB). Hệ thống tiếp tục chạy ngầm 24/7.'),
                          backgroundColor: Color(0xFF16A34A),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // LỊCH SỬ SỰ CỐ ÂM THANH YAMNET
                  if (_noiseIncidents.isNotEmpty) ...[
                    const Text('Nhật Ký Sự Cố Âm Thanh & AI YAMNet:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    ..._noiseIncidents.take(4).map((item) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.psychology, color: Color(0xFFDC2626), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${item['db']} dB: ${item['type']}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                                ),
                              ),
                              Text(
                                '${item['time']}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFFDC2626)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Thông báo quyền riêng tư
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: Color(0xFF64748B), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Để bảo vệ quyền riêng tư gia đình, tài khoản Thành Viên / Trẻ Em chỉ có thể cập nhật vị trí của chính mình gửi cho Ba Mẹ, không xem được vị trí của người khác.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // B. VAI TRÒ TRẺ EM: 4. GIỜ SỬ DỤNG MÁY & LỊCH TRÌNH
  // ==============================================================
  Widget _buildChildScheduleAndLimitsTab() {
    final int usedMinutes = _todayUsedSeconds ~/ 60;
    final int usedSecondsRem = _todayUsedSeconds % 60;
    final int effectiveDailyLimit = _todayBaseLimitMinutes + _approvedExtraMinutes;
    final int remainingMinutes = (effectiveDailyLimit - usedMinutes).clamp(0, 99999);
    final double progress = effectiveDailyLimit > 0
        ? (_todayUsedSeconds / (effectiveDailyLimit * 60.0)).clamp(0.0, 1.0)
        : 0.0;
    final bool isOver = (_todayUsedSeconds >= effectiveDailyLimit * 60 && effectiveDailyLimit > 0) || _isScreenTimeOverLimit;

    final Color statusColor = isOver
        ? const Color(0xFFDC2626)
        : (progress >= 0.8 ? const Color(0xFFEA580C) : const Color(0xFF0D9488));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thẻ Thời Gian Sử Dụng Thiết Bị Hôm Nay (Tính năng thời gian thực)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.timer_outlined, color: statusColor, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Thời Gian Dùng Máy Hôm Nay',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'ĐANG ĐẾM THỜI GIAN THỰC',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Chỉ số thời gian lớn
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$usedMinutes',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'phút ${usedSecondsRem.toString().padLeft(2, '0')}s',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        isOver
                            ? 'ĐÃ HẾT GIỜ!'
                            : 'Còn lại: $remainingMinutes phút',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isOver ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Thanh tiến trình
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Chi tiết hạn mức
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Giới hạn gốc: $_todayBaseLimitMinutes phút',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (_approvedExtraMinutes > 0)
                          Text(
                            '+ Thêm: $_approvedExtraMinutes phút',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                          ),
                        Text(
                          'Tổng hạn mức: $effectiveDailyLimit phút',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),

                  // Cảnh báo nếu hết giờ
                  if (isOver) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đã hết thời gian sử dụng thiết bị cho phép hôm nay! Hãy xin phép Ba Mẹ để được cấp thêm giờ.',
                              style: TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Bảng nút kiểm thử nhanh / Mô phỏng thời gian sử dụng
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Kiểm thử nhanh:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _buildQuickUsageChip('+5 Phút', 5),
                          _buildQuickUsageChip('+15 Phút', 15),
                          _buildQuickUsageChip('+30 Phút', 30),
                          InkWell(
                            onTap: _resetTodayScreenTime,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: const Text('Reset', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.more_time),
            label: const Text('Xin Phép Thêm Giờ Sử Dụng Thiết Bị', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: _showChildRequestDialog,
          ),
          const SizedBox(height: 20),

          const Text('Lịch Trình Sinh Hoạt Do Ba Mẹ Đặt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),

          _schedules.isEmpty
              ? const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Chưa có lịch trình nào'))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _schedules.length,
                  itemBuilder: (ctx, i) {
                    final s = _schedules[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s['scheduleType'] == 'SLEEP' ? const Color(0xFF4338CA) : const Color(0xFF0D9488),
                          child: Icon(s['scheduleType'] == 'SLEEP' ? Icons.nightlight_round : Icons.menu_book, color: Colors.white),
                        ),
                        title: Text(s['title'] ?? 'Lịch trình', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Khung giờ: ${s['startTime']} - ${s['endTime']}\n${s['lockDeviceDuringSchedule'] == true ? "🔒 Khóa thiết bị trong giờ này" : "🔓 Không khóa máy"}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ==============================================================
  // B. VAI TRÒ TRẺ EM: 5. QUÉT MÃ QR BA MẸ ĐỂ GHÉP NỐI VÀO GIA ĐÌNH
  // ==============================================================
  Widget _buildChildQrScannerTab() {
    final bool hasJoined = _group.isNotEmpty && _group['id'] != null;
    final String groupName = _group['name'] ?? 'Không Gian Gia Đình Đức Minh';
    final String ownerName = _group['ownerId'] ?? 'Ba Mẹ';
    final String parentInviteCode = _group['inviteCode'] ?? 'FAM-769610';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Banner hướng dẫn
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tham Gia Không Gian Gia Đình',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Con hãy hướng camera quét mã QR trên máy Ba Mẹ hoặc nhập mã do Ba Mẹ gửi để tham gia nhóm!',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Thẻ Trạng thái liên kết (Tuyệt đối KHÔNG sinh ra mã mới của con)
          Card(
            color: hasJoined ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: hasJoined ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasJoined ? Icons.verified_user : Icons.link_off,
                        color: hasJoined ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasJoined ? 'Đã Ghép Nối Với Gia Đình Của Ba Mẹ' : 'Chưa Liên Kết Gia Đình',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: hasJoined ? const Color(0xFF166534) : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasJoined ? '👨‍👩‍👧 Nhóm gia đình: $groupName' : 'Con chưa kết nối vào Không Gian Gia Đình nào.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasJoined
                        ? '🛡️ Người giám hộ: $ownerName • Chế độ bảo vệ 24/7 đang bật'
                        : 'Vui lòng quét mã QR hoặc nhập mã do Ba Mẹ gửi để kích hoạt bảo vệ an toàn.',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasJoined ? const Color(0xFF15803D) : const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2.1. DANH SÁCH THÀNH VIÊN TRONG GIA ĐÌNH (Tất cả thành viên đều xem được khi tham gia nhóm)
          _buildFamilyMembersListWidget(isOwnerView: false),
          const SizedBox(height: 16),

          // 3. Nút mở Camera quét mã QR Ba Mẹ
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
            icon: const Icon(Icons.camera_alt_outlined, size: 24),
            label: const Text(
              'MỞ CAMERA QUÉT MÃ QR BA MẸ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
            ),
            onPressed: _openQrScanner,
          ),
          const SizedBox(height: 16),

          // 4. Nhập thủ công mã mời do Ba Mẹ cung cấp
          Card(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hoặc Nhập Mã Mời Của Ba Mẹ Cung Cấp:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Hỏi Ba Mẹ mã mời hiển thị trong mục "Mã QR Gia Đình" rồi nhập vào đây:',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _childManualInviteCtrl,
                          decoration: InputDecoration(
                            hintText: 'Nhập mã mời của Ba Mẹ (vd: $parentInviteCode)',
                            prefixIcon: const Icon(Icons.vpn_key_outlined, color: Color(0xFF7C3AED)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final code = _childManualInviteCtrl.text.trim();
                          if (code.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Vui lòng nhập mã mời do Ba Mẹ cung cấp!'),
                                backgroundColor: AppTheme.warning,
                              ),
                            );
                            return;
                          }
                          _handleScannedQrResult(code);
                        },
                        child: const Text('Ghép Nối', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C3AED),
                        side: const BorderSide(color: Color(0xFFC4B5FD)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: Text('Mô phỏng Quét mã QR Ba Mẹ ($parentInviteCode)'),
                      onPressed: () => _handleScannedQrResult('FAMILY_INVITE:$parentInviteCode'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PHẦN 5.3: QUÉT MÃ QR (QR SCANNER TAB)
  // ==========================================
  Widget _buildQrTab() {
    final inviteCode = _group['inviteCode'] ?? 'FAM-769610';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thẻ hiển thị mã QR gia đình (Tone tím Lavender tươi sáng)
          Card(
            color: const Color(0xFFFAF5FF),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE9D5FF), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Mã QR Không Gian Gia Đình (Family Space)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF6B21A8))),
                  const SizedBox(height: 6),
                  const Text('Quét mã này từ thiết bị khác để liên kết nhanh', style: TextStyle(color: Color(0xFF7E22CE), fontSize: 12)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: QrImageView(
                      data: 'FAMILY_INVITE:$inviteCode',
                      version: QrVersions.auto,
                      size: 160.0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Chip(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFD8B4FE)),
                    label: Text('Mã mời: $inviteCode', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFF7E22CE))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nút mở Camera quét mã QR thực tế bằng MobileScanner
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
            ),
            icon: const Icon(Icons.qr_code_scanner, size: 24),
            label: const Text(
              'MỞ CAMERA QUÉT MÃ QR',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: _openQrScanner,
          ),
          const SizedBox(height: 12),

          if (isOwner)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.purpleAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.admin_panel_settings, color: Colors.purpleAccent),
              label: const Text('Phân Quyền Thành Viên Qua Nhập Mã', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
              onPressed: () => _showQrAssignDialog(),
            ),
          const SizedBox(height: 16),
          _buildFamilyMembersListWidget(isOwnerView: true),
        ],
      ),
    );
  }


  // ==========================================
  // TAB GIỚI HẠN ỨNG DỤNG (APP RULES CRUD)
  // ==========================================
  Widget _buildAppRulesTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orangeAccent,
        icon: const Icon(Icons.add_moderator),
        label: const Text('Thêm Giới Hạn App'),
        onPressed: () => _showAddAppRuleDialog(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Thống Kê & Giám Sát Thời Gian Sử Dụng Của Con Dành Cho Ba Mẹ
          _buildParentScreenTimeMonitorCard(),

          // Banner Chế độ Chạy Ngầm & Chặn Ứng Dụng
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security_update_good, color: Colors.white, size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Chế Độ Chạy Ngầm Giám Sát Thiết Bị Con 24/7',
                        style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Khi con bấm Home hoặc thoát khỏi ứng dụng, ứng dụng vẫn chạy ngầm liên tục qua Dịch vụ Trợ Năng (Accessibility Service) và Quản lý Ứng Dụng (UsageStats). Mọi ứng dụng có công tắc đỏ bật bên dưới sẽ tự động bị chặn ngay khi mở!',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFC2410C),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_circle_filled, size: 18),
                  label: const Text(
                    '🧪 Thử Nghiệm: Giả Lập Con Thoát App Mở TikTok / Game Cấm',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _simulateChildOpeningProhibitedApp(),
                ),
              ],
            ),
          ),
          if (_appRules.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('Chưa có quy tắc ứng dụng nào', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            ..._appRules.map((r) {
                final isBlocked = r['isBlocked'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isBlocked ? Colors.red.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                      child: Icon(
                        isBlocked ? Icons.block : Icons.access_time_filled,
                        color: isBlocked ? Colors.redAccent : Colors.orangeAccent,
                      ),
                    ),
                    title: Text(r['appName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isBlocked
                          ? '⛔ Đang chặn hoàn toàn • ${r['category']}'
                          : 'Giới hạn: ${r['dailyLimitMinutes']} phút/ngày (Đã dùng: ${r['usedMinutesToday']}p)',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isBlocked,
                          activeThumbColor: Colors.redAccent,
                          onChanged: (v) async {
                            await _service.toggleBlockApp(r['id']);
                            _loadAllData();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showAddAppRuleDialog(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          onPressed: () async {
                            await _service.deleteAppRule(r['id']);
                            _loadAllData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }

  // ==========================================
  // TAB LỊCH TRÌNH SINH HOẠT & GIÁM SÁT ĐỊA ĐIỂM (SCHEDULES & PRESENCE)
  // ==========================================
  Widget _buildSchedulesTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Thêm Địa Điểm & Khung Giờ', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showAddScheduleDialog(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Giải thích Tính Năng Giám Sát Vị Trí Theo Khung Giờ
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giám Sát Có Mặt Tại Địa Điểm 24/7',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Cài đặt trường học, lớp học thêm và khung giờ. Nếu con vắng mặt đúng giờ, hệ thống sẽ phát cảnh báo khẩn cấp về máy Ba Mẹ ngay lập tức.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_schedules.isEmpty)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text('Chưa có lịch trình giám sát địa điểm nào', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Nhấn nút bên dưới để thêm trường học, lớp học thêm cho con', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showAddScheduleDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm Ngay'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _schedules.length,
                itemBuilder: (ctx, i) {
                  final s = _schedules[i];
                  final isActive = s['isActive'] == true;
                  final isRequireLocation = s['requireLocationPresence'] == true;
                  final eval = _evaluateSchedulePresence(s);
                  final isAbsent = eval['isAbsent'] == true;
                  final isInSchedule = eval['isInSchedule'] == true;
                  final statusText = eval['statusText'] as String? ?? '';
                  final badgeColor = eval['badgeColor'] as Color? ?? Colors.grey;

                  final targetLat = (s['targetLatitude'] is num) ? (s['targetLatitude'] as num).toDouble() : 10.8505;
                  final targetLng = (s['targetLongitude'] is num) ? (s['targetLongitude'] as num).toDouble() : 106.7720;
                  final locName = s['targetLocationName'] ?? 'Địa điểm chỉ định';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    elevation: isAbsent ? 3 : 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isAbsent
                            ? const Color(0xFFDC2626)
                            : (isRequireLocation ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0)),
                        width: isAbsent ? 2.0 : 1.2,
                      ),
                    ),
                    color: isAbsent ? const Color(0xFFFEF2F2) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Loại lịch + Trạng thái kích hoạt
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isRequireLocation
                                      ? (isAbsent ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE))
                                      : const Color(0xFFEDE9FE),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isRequireLocation ? Icons.location_on : (s['scheduleType'] == 'SLEEP' ? Icons.bedtime : Icons.menu_book),
                                  color: isRequireLocation
                                      ? (isAbsent ? const Color(0xFFDC2626) : const Color(0xFF0284C7))
                                      : const Color(0xFF7C3AED),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s['title'] ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isAbsent ? const Color(0xFF991B1B) : AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (isRequireLocation)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0F2FE),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFBAE6FD)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.map, size: 11, color: Color(0xFF0284C7)),
                                                SizedBox(width: 3),
                                                Text('VIETMAP GPS', style: TextStyle(color: Color(0xFF0369A1), fontSize: 9, fontWeight: FontWeight.w900)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Áp dụng cho bé: ${s['childUsername'] ?? "Tất cả"} • ${s['daysOfWeek']}',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isActive,
                                activeThumbColor: const Color(0xFF0284C7),
                                onChanged: (v) async {
                                  await _service.toggleScheduleActive(s['id']);
                                  _loadAllData();
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 20),

                          // Chi tiết Địa điểm & Khung giờ
                          if (isRequireLocation) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.place, size: 16, color: Color(0xFF0284C7)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Địa điểm: $locName',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      ),
                                      if (s['targetAddress'] != null && s['targetAddress'].toString().isNotEmpty)
                                        Text(
                                          '${s['targetAddress']}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],

                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 16, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(
                                'Khung giờ: ${s['startTime']} - ${s['endTime']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB45309)),
                              ),
                              if (isRequireLocation) ...[
                                const SizedBox(width: 12),
                                Text(
                                  '• Bán kính: ${s['targetRadiusMeters'] ?? 300}m',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),

                          // BADGE TRẠNG THÁI CÓ MẶT THỜI GIAN THỰC
                          if (isRequireLocation) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isAbsent ? Icons.warning_rounded : (isInSchedule ? Icons.check_circle : Icons.schedule),
                                    color: badgeColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      statusText,
                                      style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Nút hành động
                          Row(
                            children: [
                              if (isRequireLocation)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0.5,
                                  ),
                                  icon: const Icon(Icons.map, size: 14),
                                  label: const Text('Bản đồ VietMap', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    VietmapFullScreenDialog.show(
                                      context,
                                      memberName: 'Địa điểm: $locName',
                                      roleName: 'Vị trí bắt buộc có mặt',
                                      latitude: targetLat,
                                      longitude: targetLng,
                                      address: s['targetAddress'] ?? locName,
                                    );
                                  },
                                ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0284C7)),
                                tooltip: 'Chỉnh sửa',
                                onPressed: () => _showAddScheduleDialog(s),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                tooltip: 'Xóa lịch trình',
                                onPressed: () async {
                                  await _service.deleteSchedule(s['id']);
                                  _loadAllData();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }



  // ==============================================================
  // A. VAI TRÒ CHỦ GIA ĐÌNH: 2. BẢNG ĐIỀU KHIỂN & KHÓA THIẾT BỊ CON TỪ XA
  // (PARENTAL MDM & REMOTE DEVICE LOCKOUT)
  // ==============================================================
  Widget _buildOwnerDeviceLockTab() {
    // Thu thập danh sách thành viên con từ _members và _locations
    final List<Map<String, dynamic>> childMembers = [];
    final seen = <String>{};

    for (final m in _members) {
      final uname = (m['username'] ?? '').toString();
      final role = (m['role'] ?? '').toString().toLowerCase();
      if (uname.isNotEmpty && uname != widget.username && role != 'owner' && role != 'admin' && !seen.contains(uname)) {
        seen.add(uname);
        childMembers.add(Map<String, dynamic>.from(m));
      }
    }

    for (final l in _locations) {
      final uname = (l['username'] ?? '').toString();
      final role = (l['role'] ?? '').toString().toLowerCase();
      if (uname.isNotEmpty && uname != widget.username && role != 'owner' && role != 'admin' && !seen.contains(uname)) {
        seen.add(uname);
        childMembers.add(Map<String, dynamic>.from(l));
      }
    }

    // Luôn đồng bộ trạng thái khóa và vị trí mới nhất từ _locations vào childMembers
    for (final c in childMembers) {
      final uname = c['username']?.toString() ?? '';
      final loc = _locations.firstWhere(
        (l) => (l['username']?.toString().toLowerCase() == uname.toLowerCase()),
        orElse: () => {},
      );
      if (loc.isNotEmpty) {
        if (loc['addressName'] != null && (loc['addressName'] as String).isNotEmpty) {
          c['addressName'] = loc['addressName'];
        }
        c['isDeviceLocked'] = loc['isDeviceLocked'] == true;
      }
    }

    if (childMembers.isEmpty && widget.username != 'duc') {
      childMembers.add({
        'username': 'duc',
        'role': 'Child',
        'isDeviceLocked': false,
        'addressName': 'Khu Công Nghệ Cao, TP. Thủ Đức, TP. Hồ Chí Minh',
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Giới thiệu Hệ thống Kiểm soát Thiết bị
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.phonelink_lock, color: Colors.white, size: 36),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HỆ THỐNG KHÓA MÁY CON TỪ XA (MDM)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '🛡️ Khóa màn hình cưỡng chế ngay tức khắc trên thiết bị con khi cần con tập trung học bài hoặc đi ngủ. Mở khóa lại chỉ với 1 chạm duy nhất.',
                        style: TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Khung Điều khiển Lệnh Nhanh Khóa & Mở Khóa Toàn Gia Đình
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt, color: Color(0xFFDC2626), size: 20),
                    SizedBox(width: 6),
                    Text('Lệnh Điều Khiển Nhanh Toàn Gia Đình:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.phonelink_lock, size: 18),
                        label: const Text('KHÓA TẤT CẢ MÁY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          _promptLockChildDevice('Tất cả thiết bị con');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: const Text('MỞ KHÓA TẤT CẢ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          setState(() {
                            for (final c in childMembers) { c['isDeviceLocked'] = false; }
                            for (final m in _members) { m['isDeviceLocked'] = false; }
                            for (final l in _locations) { l['isDeviceLocked'] = false; }
                          });
                          await _service.setChildLock(childUsername: 'all', isLocked: false);
                          for (final c in childMembers) {
                            final name = c['username'] ?? '';
                            if (name.isNotEmpty) {
                              await _service.setChildLock(childUsername: name, isLocked: false);
                            }
                          }
                          await _loadAllData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🔓 Đã phát lệnh MỞ KHÓA toàn bộ thiết bị con thành công!'),
                                backgroundColor: Color(0xFF16A34A),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.phonelink_lock, size: 16),
                    label: const Text('🧪 Khóa Thử Nghiệm Màn Hình Này', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() => _isTestLockActive = true);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('Danh Sách Thiết Bị Của Con Được Quản Lý:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),

          if (childMembers.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.devices_other, size: 44, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 8),
                  const Text('Chưa có thiết bị con nào trong nhóm gia đình.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('Cho Con Quét Mã QR Để Kết Nối'),
                    onPressed: () => _tabController.animateTo(5),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...childMembers.map((c) {
              final childName = c['username'] ?? 'Con yêu';
              final role = (c['role'] ?? 'Child').toString();
              final bool isDeviceLocked = c['isDeviceLocked'] == true;
              final addressName = c['addressName'] ?? 'Đang cập nhật vị trí...';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDeviceLocked ? const Color(0xFFF87171) : const Color(0xFFCBD5E1),
                    width: isDeviceLocked ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDeviceLocked ? Colors.redAccent.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isDeviceLocked ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
                          child: Icon(
                            isDeviceLocked ? Icons.phonelink_lock : Icons.smartphone,
                            color: isDeviceLocked ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Điện thoại của: $childName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                              ),
                              Text(
                                'Vai trò: $role • Android Phone',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        // Badge Trạng thái
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDeviceLocked ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDeviceLocked ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDeviceLocked ? Icons.lock : Icons.check_circle,
                                size: 12,
                                color: isDeviceLocked ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDeviceLocked ? '🔴 ĐANG KHÓA' : '🟢 HOẠT ĐỘNG',
                                style: TextStyle(
                                  color: isDeviceLocked ? const Color(0xFF991B1B) : const Color(0xFF166534),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Icon(
                          isDeviceLocked ? Icons.lock_clock : Icons.place,
                          size: 14,
                          color: isDeviceLocked ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isDeviceLocked
                                ? '⚠️ Màn hình máy con đang bị khóa cứng. Con chỉ gọi được số khẩn cấp của Ba Mẹ.'
                                : '📍 Vị trí: $addressName',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDeviceLocked ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                              fontWeight: isDeviceLocked ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // CÁC NÚT ĐIỀU KHIỂN KHÓA & MỞ KHÓA
                    Row(
                      children: [
                        // Nút 1: Khóa máy con (Chỉ hiện khi chưa khóa)
                        if (!isDeviceLocked) ...[
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 2,
                              ),
                              icon: const Icon(Icons.phonelink_lock, size: 16),
                              label: const Text(
                                '🔒 KHÓA MÁY CON',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _promptLockChildDevice(childName),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],

                        // Nút 2: Nút MỞ KHÓA LUÔN (Người dùng yêu cầu: có 1 nút riêng để mở khóa luôn khi khóa)
                        Expanded(
                          flex: isDeviceLocked ? 4 : 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: isDeviceLocked ? 3 : 1,
                            ),
                            icon: const Icon(Icons.lock_open, size: 16),
                            label: Text(
                              isDeviceLocked ? '🔓 MỞ KHÓA LUÔN' : 'Mở Khóa',
                              style: TextStyle(
                                fontSize: isDeviceLocked ? 13 : 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            onPressed: () async {
                              setState(() {
                                c['isDeviceLocked'] = false;
                                for (final m in _members) {
                                  if (m['username']?.toString().toLowerCase() == childName.toLowerCase()) {
                                    m['isDeviceLocked'] = false;
                                  }
                                }
                                for (final l in _locations) {
                                  if (l['username']?.toString().toLowerCase() == childName.toLowerCase()) {
                                    l['isDeviceLocked'] = false;
                                  }
                                }
                              });
                              final res = await _service.setChildLock(childUsername: childName, isLocked: false);
                              await _loadAllData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(res['message'] ?? '🔓 Đã mở khóa điện thoại cho $childName thành công!'),
                                    backgroundColor: const Color(0xFF16A34A),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Nút 3: Xem trước màn hình khóa
                        IconButton(
                          icon: const Icon(Icons.visibility, color: Color(0xFF0284C7)),
                          tooltip: 'Xem màn hình khóa của con',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => Dialog(
                                insetPadding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                child: SizedBox(
                                  height: 520,
                                  child: _buildChildLockedScreen(isPreview: true),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
