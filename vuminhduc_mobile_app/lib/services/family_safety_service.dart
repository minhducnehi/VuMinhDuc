import 'dart:convert';
import 'api_client.dart';

class FamilySafetyService {
  final ApiClient _api = ApiClient();

  // 1. Nhóm gia đình & QR code kết nối
  Future<Map<String, dynamic>> getFamilyGroup(String username) async {
    try {
      final res = await _api.get('FamilySafety/group?username=$username');
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  // Phân quyền cho thành viên qua quét mã QR
  Future<Map<String, dynamic>> qrAssignRole({
    required String ownerUsername,
    required String memberUsername,
    required String assignedRole,
    required String inviteCode,
  }) async {
    try {
      final res = await _api.post('FamilySafety/qr-assign-role', body: {
        'ownerUsername': ownerUsername,
        'memberUsername': memberUsername,
        'assignedRole': assignedRole,
        'inviteCode': inviteCode,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // Đổi vai trò thành viên trực tiếp trong nhóm gia đình (Thành viên ↔ Trẻ em)
  Future<Map<String, dynamic>> assignMemberRole({
    required String ownerUsername,
    required String memberUsername,
    required String assignedRole,
  }) async {
    try {
      final res = await _api.post('FamilySafety/assign-member-role', body: {
        'ownerUsername': ownerUsername,
        'memberUsername': memberUsername,
        'assignedRole': assignedRole,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // Lấy danh sách toàn bộ thành viên trong nhóm gia đình kèm vai trò
  Future<List<Map<String, dynamic>>> getFamilyMembers() async {
    try {
      final res = await _api.get('FamilySafety/members');
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> childJoinQr({
    required String childUsername,
    required String inviteCode,
  }) async {
    try {
      final res = await _api.post('FamilySafety/child-join-qr', body: {
        'childUsername': childUsername,
        'inviteCode': inviteCode,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // 2. Chia sẻ vị trí thời gian thực (Location Sharing)
  Future<bool> updateLocation({
    required String username,
    required double latitude,
    required double longitude,
    double speed = 0,
    String address = '',
  }) async {
    try {
      final res = await _api.post('FamilySafety/location', body: {
        'username': username,
        'userId': username,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'addressName': address,
      });
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getMemberLocations() async {
    try {
      final res = await _api.get('FamilySafety/locations');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Lấy nhật ký lịch sử lộ trình di chuyển của thành viên theo ngày
  Future<List<Map<String, dynamic>>> getLocationHistory(String childUsername, {String? date}) async {
    try {
      final dateParam = date != null ? '&date=$date' : '';
      final res = await _api.get('FamilySafety/location-history?childUsername=$childUsername$dateParam');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // 3. Cảm biến & Cảnh báo SOS
  Future<Map<String, dynamic>> sendSafetyAlert({
    required String username,
    required String alertType,
    required String message,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final res = await _api.post('FamilySafety/alert', body: {
        'username': username,
        'userId': username,
        'alertType': alertType,
        'message': message,
        'latitude': latitude,
        'longitude': longitude,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<List<Map<String, dynamic>>> getAlerts() async {
    try {
      final res = await _api.get('FamilySafety/alerts');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> resolveAlert(int id) async {
    try {
      final res = await _api.post('FamilySafety/alert/resolve/$id');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 4. Yêu cầu từ Trẻ em
  Future<Map<String, dynamic>> sendChildRequest({
    required String childUsername,
    required String requestType,
    required int extraMinutes,
    required String note,
  }) async {
    try {
      final res = await _api.post('FamilySafety/child-request', body: {
        'childUsername': childUsername,
        'childId': childUsername,
        'requestType': requestType,
        'extraMinutes': extraMinutes,
        'note': note,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<List<Map<String, dynamic>>> getChildRequests() async {
    try {
      final res = await _api.get('FamilySafety/child-requests');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> handleChildRequest(int id, String action, String approver) async {
    try {
      final res = await _api.post('FamilySafety/child-request/action/$id?action=$action&approver=$approver');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 5. Trợ lý AI Hệ thống
  Future<Map<String, dynamic>> askAiAssistant({
    required String userRole,
    required String username,
    required String message,
  }) async {
    try {
      final res = await _api.post('FamilySafety/ai-assistant', body: {
        'userRole': userRole,
        'username': username,
        'message': message,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'reply': 'Lỗi kết nối máy chủ AI: $e'};
    }
  }

  // ==============================================================
  // 6. QUẢN LÝ THIẾT BỊ CON (Devices CRUD - 5.5 ĐIỂM)
  // ==============================================================
  Future<List<Map<String, dynamic>>> getDevices({String? childUsername, String? parentUsername}) async {
    try {
      String query = '';
      if (childUsername != null) query += 'childUsername=$childUsername&';
      if (parentUsername != null) query += 'parentUsername=$parentUsername';
      final res = await _api.get('FamilySafety/devices?$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> addDevice({
    required String deviceName,
    required String deviceType,
    required String deviceIdentifier,
    required String childUsername,
    required String parentUsername,
  }) async {
    try {
      final res = await _api.post('FamilySafety/devices', body: {
        'deviceName': deviceName,
        'deviceType': deviceType,
        'deviceIdentifier': deviceIdentifier,
        'childUsername': childUsername,
        'parentUsername': parentUsername,
        'batteryLevel': 85,
        'isLocked': false,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateDevice(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.put('FamilySafety/devices/$id', body: data);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<bool> deleteDevice(int id) async {
    try {
      final res = await _api.delete('FamilySafety/devices/$id');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> toggleLockDevice(int id) async {
    try {
      final res = await _api.post('FamilySafety/devices/$id/toggle-lock');
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  /// Khóa hoặc Mở khóa điện thoại của con từ xa bằng tên tài khoản con kèm lý do và mã PIN
  Future<Map<String, dynamic>> setChildLock({
    required String childUsername,
    required bool isLocked,
    String? reason,
    String? unlockPin,
  }) async {
    try {
      final res = await _api.post('FamilySafety/lock-child', body: {
        'childUsername': childUsername,
        'isLocked': isLocked,
        'reason': reason ?? '',
        'unlockPin': unlockPin ?? '',
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'status': false, 'message': 'Không thể kết nối máy chủ'};
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  /// Kiểm tra chi tiết trạng thái khóa máy và lý do khóa
  Future<Map<String, dynamic>> getChildLockInfo(String childUsername) async {
    try {
      final res = await _api.get('FamilySafety/child-lock-status?childUsername=$childUsername');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {
          'isLocked': data['isLocked'] == true,
          'reason': data['reason']?.toString() ?? '',
        };
      }
      return {'isLocked': false, 'reason': ''};
    } catch (_) {
      return {'isLocked': false, 'reason': ''};
    }
  }

  /// Kiểm tra xem thiết bị của con hiện tại có đang bị khóa hay không
  Future<bool> getChildLockStatus(String childUsername) async {
    final info = await getChildLockInfo(childUsername);
    return info['isLocked'] == true;
  }

  /// Mở khóa bằng mã PIN phụ huynh đã cài đặt
  Future<Map<String, dynamic>> verifyUnlockPin({
    required String childUsername,
    required String pin,
  }) async {
    try {
      final res = await _api.post('FamilySafety/verify-unlock-pin', body: {
        'childUsername': childUsername,
        'pin': pin,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  /// Khách hàng / Con đồng ý cấp quyền kiểm soát điện thoại (Quản trị viên, giám sát, khóa máy)
  Future<bool> grantSupervision({
    required String childUsername,
    String deviceName = 'Điện thoại di động',
  }) async {
    try {
      final res = await _api.post('FamilySafety/grant-supervision', body: {
        'childUsername': childUsername,
        'deviceName': deviceName,
        'granted': true,
      });
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==============================================================
  // 7. QUẢN LÝ ỨNG DỤNG & GIỚI HẠN THỜI GIAN (App Rules CRUD)
  // ==============================================================
  Future<List<Map<String, dynamic>>> getAppRules({String? childUsername}) async {
    try {
      String query = childUsername != null ? '?childUsername=$childUsername' : '';
      final res = await _api.get('FamilySafety/app-rules$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createAppRule({
    required String childUsername,
    required String appName,
    required String appPackage,
    required int dailyLimitMinutes,
    required String category,
    bool isBlocked = false,
  }) async {
    try {
      final res = await _api.post('FamilySafety/app-rules', body: {
        'childUsername': childUsername,
        'appName': appName,
        'appPackage': appPackage,
        'dailyLimitMinutes': dailyLimitMinutes,
        'usedMinutesToday': 0,
        'category': category,
        'isBlocked': isBlocked,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateAppRule(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.put('FamilySafety/app-rules/$id', body: data);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<bool> deleteAppRule(int id) async {
    try {
      final res = await _api.delete('FamilySafety/app-rules/$id');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> toggleBlockApp(int id) async {
    try {
      final res = await _api.post('FamilySafety/app-rules/$id/toggle-block');
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }


  /// Ghi nhận và tích lũy thời gian sử dụng thiết bị / ứng dụng của con
  Future<Map<String, dynamic>> recordUsage({
    required String childUsername,
    required int additionalMinutes,
    String? appName,
  }) async {
    try {
      final res = await _api.post('FamilySafety/record-usage', body: {
        'childUsername': childUsername,
        'additionalMinutes': additionalMinutes,
        'appName': appName ?? '',
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'status': false};
    } catch (_) {
      return {'status': false};
    }
  }

  /// Lấy thống kê chi tiết thời gian sử dụng thiết bị hôm nay của con
  Future<Map<String, dynamic>> getScreenTimeStats(String childUsername) async {
    try {
      final res = await _api.get('FamilySafety/screen-time-stats?childUsername=$childUsername');
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'status': false};
    } catch (_) {
      return {'status': false};
    }
  }

  // ==============================================================
  // 8. QUẢN LÝ LỊCH TRÌNH SINH HOẠT / HỌC TẬP (Schedules CRUD)
  // ==============================================================
  Future<List<Map<String, dynamic>>> getSchedules({String? childUsername}) async {
    try {
      String query = childUsername != null ? '?childUsername=$childUsername' : '';
      final res = await _api.get('FamilySafety/schedules$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createSchedule({
    required String childUsername,
    required String title,
    required String scheduleType,
    required String startTime,
    required String endTime,
    required String daysOfWeek,
    bool lockDevice = true,
    bool requireLocationPresence = false,
    String? targetLocationName,
    String? targetAddress,
    double? targetLatitude,
    double? targetLongitude,
    double targetRadiusMeters = 300.0,
  }) async {
    try {
      final res = await _api.post('FamilySafety/schedules', body: {
        'childUsername': childUsername,
        'title': title,
        'scheduleType': scheduleType,
        'startTime': startTime,
        'endTime': endTime,
        'daysOfWeek': daysOfWeek,
        'lockDeviceDuringSchedule': lockDevice,
        'isActive': true,
        'requireLocationPresence': requireLocationPresence,
        'targetLocationName': targetLocationName,
        'targetAddress': targetAddress,
        'targetLatitude': targetLatitude,
        'targetLongitude': targetLongitude,
        'targetRadiusMeters': targetRadiusMeters,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> checkSchedulePresence({
    required String childUsername,
    required double latitude,
    required double longitude,
    String? addressName,
  }) async {
    try {
      final res = await _api.post('FamilySafety/check-schedule-presence', body: {
        'childUsername': childUsername,
        'latitude': latitude,
        'longitude': longitude,
        'addressName': addressName ?? '',
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'hasSchedule': false, 'isCompliant': true, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> updateSchedule(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.put('FamilySafety/schedules/$id', body: data);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<bool> deleteSchedule(int id) async {
    try {
      final res = await _api.delete('FamilySafety/schedules/$id');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> toggleScheduleActive(int id) async {
    try {
      final res = await _api.post('FamilySafety/schedules/$id/toggle-active');
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // ==============================================================
  // 9. VÙNG AN TOÀN (Geofencing CRUD)
  // ==============================================================
  Future<List<Map<String, dynamic>>> getSafeZones({String? childUsername}) async {
    try {
      String query = childUsername != null ? '?childUsername=$childUsername' : '';
      final res = await _api.get('FamilySafety/safe-zones$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createSafeZone({
    required String childUsername,
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    try {
      final res = await _api.post('FamilySafety/safe-zones', body: {
        'childUsername': childUsername,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'isActive': true,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<bool> deleteSafeZone(int id) async {
    try {
      final res = await _api.delete('FamilySafety/safe-zones/$id');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> checkGeofence({
    required String childUsername,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final res = await _api.post('FamilySafety/check-geofence', body: {
        'childUsername': childUsername,
        'latitude': latitude,
        'longitude': longitude,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // ==============================================================
  // 10. AI DIGITAL DETOX & MOOD COMPANION
  // ==============================================================
  Future<List<Map<String, dynamic>>> getMoodEntries({String? childUsername}) async {
    try {
      String query = childUsername != null ? '?childUsername=$childUsername' : '';
      final res = await _api.get('FamilySafety/mood-entries$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> addMoodEntry({
    required String childUsername,
    required String mood,
    required int screenTimeMinutes,
    required String note,
  }) async {
    try {
      final res = await _api.post('FamilySafety/mood-entries', body: {
        'childUsername': childUsername,
        'mood': mood,
        'screenTimeMinutes': screenTimeMinutes,
        'note': note,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  // ==============================================================
  // 11. BẢO VỆ AN TOÀN & CHẶN ĐƯỜNG LINK LẠ / WEB KHÔNG AN TOÀN
  // ==============================================================
  Future<Map<String, dynamic>> checkWebUrl({
    required String childUsername,
    required String url,
  }) async {
    try {
      final res = await _api.post('FamilySafety/check-web-url', body: {
        'childUsername': childUsername,
        'url': url,
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'status': false, 'isBlocked': false, 'message': 'Không thể kết nối máy chủ'};
    } catch (e) {
      return {'status': false, 'isBlocked': false, 'message': '$e'};
    }
  }

  // ==============================================================
  // 12. TỰ ĐỘNG CHẶN TRUY CẬP & TẢI XUỐNG NGUY HIỂM (AUTO-SHIELD)
  // Không cần phụ huynh phải gắn link vô kiểm tra thủ công
  // ==============================================================
  Future<Map<String, dynamic>> triggerAutoBlock({
    required String childUsername,
    required String actionType,
    required String targetName,
    required String category,
  }) async {
    try {
      final res = await _api.post('FamilySafety/auto-block', body: {
        'childUsername': childUsername,
        'actionType': actionType,
        'targetName': targetName,
        'category': category,
      });
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': false, 'message': '$e'};
    }
  }

  Future<List<Map<String, dynamic>>> getAutoBlockedLogs({String? childUsername}) async {
    try {
      String query = childUsername != null ? '?childUsername=$childUsername' : '';
      final res = await _api.get('FamilySafety/auto-blocked-logs$query');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
