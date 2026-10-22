using System;
using System.ComponentModel.DataAnnotations;

namespace VuMinhDuc.Models
{
    // Mô hình Gia đình (Family Space) do Family Owner quản lý
    public class FamilyGroup
    {
        [Key]
        public int Id { get; set; }
        public string Name { get; set; } = "Gia Đình Hạnh Phúc";
        public string OwnerId { get; set; } = string.Empty; // User ID của Owner
        public string InviteCode { get; set; } = Guid.NewGuid().ToString().Substring(0, 8).ToUpper(); // Mã QR liên kết
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // Vị trí thời gian thực của thành viên (Location Sharing)
    public class MemberLocation
    {
        [Key]
        public int Id { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        public double Speed { get; set; }
        public string AddressName { get; set; } = "Đang cập nhật";
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    // Nhật ký lộ trình di chuyển theo thời gian (Timeline & Breadcrumb Trail)
    public class MemberLocationHistory
    {
        [Key]
        public int Id { get; set; }
        public string Username { get; set; } = string.Empty;
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        public double Speed { get; set; }
        public string AddressName { get; set; } = string.Empty;
        public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
    }

    // Cảnh báo khẩn cấp SOS và cảm biến môi trường (Fall/Impact/Noise detection)
    public class SafetyAlert
    {
        [Key]
        public int Id { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public string AlertType { get; set; } = "SOS"; // "SOS", "FALL_DETECTED", "HIGH_IMPACT", "NOISE", "GEOFENCE_EXIT"
        public string Message { get; set; } = string.Empty;
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public bool IsResolved { get; set; } = false;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // Yêu cầu từ Trẻ em gửi đến Phụ huynh (Xin thêm giờ, xin cấp quyền)
    public class ChildRequest
    {
        [Key]
        public int Id { get; set; }
        public string ChildId { get; set; } = string.Empty;
        public string ChildUsername { get; set; } = string.Empty;
        public string RequestType { get; set; } = "SCREEN_TIME"; // SCREEN_TIME, APP_PERMISSION
        public int ExtraMinutes { get; set; } = 30;
        public string Note { get; set; } = string.Empty;
        public string Status { get; set; } = "PENDING"; // PENDING, APPROVED, REJECTED
        public string? ApprovedBy { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // ==========================================
    // 4 THỰC THỂ CRUD BỔ SUNG THEO YÊU CẦU ĐỀ BÀI (5.5 ĐIỂM)
    // ==========================================

    // 1. Quản lý Thiết bị con (Devices CRUD)
    public class ChildDevice
    {
        [Key]
        public int Id { get; set; }
        public string DeviceName { get; set; } = string.Empty; // Ví dụ: "Samsung Galaxy Tab S9", "Xiaomi Redmi 12"
        public string DeviceType { get; set; } = "Android"; // "Android", "iOS", "Tablet"
        public string? DeviceIdentifier { get; set; } = string.Empty; // Mã serial hoặc UUID
        public string? ChildUsername { get; set; } = string.Empty; // Tên tài khoản của trẻ em
        public string? ParentUsername { get; set; } = string.Empty; // Tên phụ huynh/chủ gia đình
        public int BatteryLevel { get; set; } = 85; // % pin
        public bool IsLocked { get; set; } = false; // Phụ huynh có thể khóa máy từ xa
        public DateTime LinkedAt { get; set; } = DateTime.UtcNow;
        public DateTime LastActiveAt { get; set; } = DateTime.UtcNow;
    }

    // 2. Quản lý Ứng dụng & Giới hạn thời gian (App Rules / Limits CRUD)
    public class AppRule
    {
        [Key]
        public int Id { get; set; }
        public string? ChildUsername { get; set; } = string.Empty;
        public string AppName { get; set; } = string.Empty; // "TikTok", "YouTube", "Roblox", "Facebook"
        public string? AppPackage { get; set; } = string.Empty; // "com.zhiliaoapp.musically"
        public int DailyLimitMinutes { get; set; } = 60; // Giới hạn phút/ngày
        public int UsedMinutesToday { get; set; } = 0; // Đã dùng hôm nay
        public bool IsBlocked { get; set; } = false; // Chặn hoàn toàn
        public string? Category { get; set; } = "Mạng xã hội"; // "Mạng xã hội", "Trò chơi", "Học tập", "Giải trí"
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // 3. Quản lý Lịch trình sinh hoạt / học tập & Có mặt tại địa điểm (Schedules CRUD)
    public class StudySchedule
    {
        [Key]
        public int Id { get; set; }
        public string? ChildUsername { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty; // "Giờ học bài tối", "Có mặt tại trường học"
        public string? ScheduleType { get; set; } = "STUDY"; // "STUDY", "SLEEP", "RELAX", "LOCATION_PRESENCE"
        public string StartTime { get; set; } = "20:00"; // Định dạng HH:mm
        public string EndTime { get; set; } = "21:30"; // Định dạng HH:mm
        public string? DaysOfWeek { get; set; } = "T2, T3, T4, T5, T6, T7, CN";
        public bool LockDeviceDuringSchedule { get; set; } = true;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Vị trí bắt buộc có mặt & Cảnh báo vắng mặt theo khung giờ (Geofencing Presence Check)
        public bool RequireLocationPresence { get; set; } = false; // Bắt buộc có mặt tại địa điểm
        public string? TargetLocationName { get; set; } = string.Empty; // "Trường Tiểu Học Tân Phú", "Lớp Học Thêm Tiếng Anh"
        public string? TargetAddress { get; set; } = string.Empty; // Địa chỉ cụ thể
        public double? TargetLatitude { get; set; } // Vĩ độ đích
        public double? TargetLongitude { get; set; } // Kinh độ đích
        public double TargetRadiusMeters { get; set; } = 300.0; // Bán kính cho phép (mét)
    }

    // 4. Quản lý Vùng an toàn (Geofencing CRUD)
    public class SafeZone
    {
        [Key]
        public int Id { get; set; }
        public string? ChildUsername { get; set; } = string.Empty;
        public string Name { get; set; } = "Trường học"; // "Trường học", "Nhà riêng", "Nhà ông bà"
        public double Latitude { get; set; } = 10.762622;
        public double Longitude { get; set; } = 106.660172;
        public double RadiusMeters { get; set; } = 300.0;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // 5. AI Digital Detox & Mood Companion
    public class MoodEntry
    {
        [Key]
        public int Id { get; set; }
        public string? ChildUsername { get; set; } = string.Empty;
        public string Mood { get; set; } = "Vui vẻ"; // "Vui vẻ", "Căng thẳng", "Mệt mỏi", "Buồn", "Hào hứng"
        public int ScreenTimeMinutes { get; set; } = 120;
        public string? Note { get; set; } = string.Empty;
        public string? AiAdvice { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
