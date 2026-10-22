using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using VuMinhDuc.Models;

namespace VuMinhDuc.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class FamilySafetyController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly UserManager<User> _userManager;
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly IMemoryCache _cache;
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> _childLockReasonStore = new(StringComparer.OrdinalIgnoreCase);
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> _childLockPinStore = new(StringComparer.OrdinalIgnoreCase);
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, DateTime> _manualUnlockExemptionStore = new(StringComparer.OrdinalIgnoreCase);
        private static readonly HttpClient _sharedHttpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(6)
        };

        public FamilySafetyController(
            ApplicationDbContext context, 
            UserManager<User> userManager,
            RoleManager<IdentityRole> roleManager,
            IMemoryCache cache)
        {
            _context = context;
            _userManager = userManager;
            _roleManager = roleManager;
            _cache = cache;
        }

        // ==========================
        // 1. NHÓM GIA ĐÌNH & MÃ QR (Chủ gia đình & Thành viên)
        // ==========================
        [HttpGet("group")]
        public async Task<IActionResult> GetFamilyGroup([FromQuery] string? username = null)
        {
            var group = await _context.FamilyGroups.FirstOrDefaultAsync();
            if (group == null)
            {
                group = new FamilyGroup
                {
                    Name = "Không Gian Gia Đình Đức Minh",
                    OwnerId = username ?? "duc",
                    InviteCode = "FAM-" + new Random().Next(100000, 999999).ToString()
                };
                _context.FamilyGroups.Add(group);
                await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            }
            return Ok(group);
        }

        /// <summary>
        /// Xóa sạch toàn bộ dữ liệu (vị trí, lịch sử lộ trình, cảnh báo, lịch trình, yêu cầu, thiết bị, quy tắc, tâm trạng)
        /// Tuyệt đối bảo toàn 100% tài khoản AspNetUsers, AspNetRoles và mật khẩu.
        /// </summary>
        [HttpPost("reset-all-data")]
        public async Task<IActionResult> ResetAllData([FromQuery] string confirm = "")
        {
            if (confirm != "CONFIRM_WIPE_ALL")
            {
                return BadRequest(new { status = false, message = "Vui lòng cung cấp mã xác nhận confirm=CONFIRM_WIPE_ALL" });
            }

            var deletedSummary = new Dictionary<string, int>();

            try
            {
                // 1. Xóa Lịch sử lộ trình di chuyển
                var histCount = await _context.MemberLocationHistories.CountAsync();
                _context.MemberLocationHistories.RemoveRange(_context.MemberLocationHistories);
                deletedSummary["Lịch sử lộ trình di chuyển"] = histCount;

                // 2. Xóa Vị trí tức thời
                var locCount = await _context.MemberLocations.CountAsync();
                _context.MemberLocations.RemoveRange(_context.MemberLocations);
                deletedSummary["Vị trí tức thời của các thành viên"] = locCount;

                // 3. Xóa Cảnh báo an toàn & SOS
                var alertCount = await _context.SafetyAlerts.CountAsync();
                _context.SafetyAlerts.RemoveRange(_context.SafetyAlerts);
                deletedSummary["Cảnh báo khẩn cấp & SOS"] = alertCount;

                // 4. Xóa Yêu cầu của trẻ em
                var reqCount = await _context.ChildRequests.CountAsync();
                _context.ChildRequests.RemoveRange(_context.ChildRequests);
                deletedSummary["Yêu cầu trẻ em xin giờ/ứng dụng"] = reqCount;

                // 5. Xóa Thiết bị của trẻ
                var devCount = await _context.ChildDevices.CountAsync();
                _context.ChildDevices.RemoveRange(_context.ChildDevices);
                deletedSummary["Thiết bị liên kết"] = devCount;

                // 6. Xóa Quy tắc ứng dụng
                var ruleCount = await _context.AppRules.CountAsync();
                _context.AppRules.RemoveRange(_context.AppRules);
                deletedSummary["Quy tắc giới hạn ứng dụng"] = ruleCount;

                // 7. Xóa Lịch trình sinh hoạt & giám sát địa điểm
                var schedCount = await _context.StudySchedules.CountAsync();
                _context.StudySchedules.RemoveRange(_context.StudySchedules);
                deletedSummary["Lịch học & giám sát địa điểm"] = schedCount;

                // 8. Xóa Vùng an toàn Geofencing
                var zoneCount = await _context.SafeZones.CountAsync();
                _context.SafeZones.RemoveRange(_context.SafeZones);
                deletedSummary["Vùng an toàn Geofencing"] = zoneCount;

                // 9. Xóa Nhật ký cảm xúc AI
                var moodCount = await _context.MoodEntries.CountAsync();
                _context.MoodEntries.RemoveRange(_context.MoodEntries);
                deletedSummary["Nhật ký tâm trạng AI"] = moodCount;

                // 10. Xóa Dữ liệu sản phẩm & bài viết nếu có
                var prodCount = await _context.Products.CountAsync();
                _context.Products.RemoveRange(_context.Products);
                deletedSummary["Sản phẩm"] = prodCount;

                var postCount = await _context.Posts.CountAsync();
                _context.Posts.RemoveRange(_context.Posts);
                deletedSummary["Bài viết"] = postCount;

                var catCount = await _context.Categories.CountAsync();
                _context.Categories.RemoveRange(_context.Categories);
                deletedSummary["Danh mục"] = catCount;

                await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

                var preservedUsers = await _userManager.Users.Select(u => u.UserName).ToListAsync();

                return Ok(new
                {
                    status = true,
                    message = "Đã dọn dẹp sạch toàn bộ dữ liệu thành công! Tất cả tài khoản và mật khẩu được bảo toàn 100%.",
                    preservedUsersCount = preservedUsers.Count,
                    preservedUsernames = preservedUsers,
                    deletedRecords = deletedSummary
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = false, message = $"Lỗi khi xóa dữ liệu: {ex.Message}" });
            }
        }

        public class QrAssignRoleRequest
        {
            public string OwnerUsername { get; set; } = string.Empty;
            public string MemberUsername { get; set; } = string.Empty;
            public string AssignedRole { get; set; } = "Member"; // "Member" (Thành viên) hoặc "Child" (Trẻ em)
            public string InviteCode { get; set; } = string.Empty;
        }

        /// <summary>
        /// Chủ gia đình phân quyền trực tiếp cho thành viên khi quét mã QR
        /// </summary>
        [HttpPost("qr-assign-role")]
        public async Task<IActionResult> QrAssignRole([FromBody] QrAssignRoleRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.MemberUsername))
                return BadRequest(new { status = false, message = "Thiếu tên thành viên cần liên kết" });

            // Kiểm tra mã mời gia đình (hỗ trợ FAMILY_INVITE: prefix và FAM-123456 mặc định)
            var group = await _context.FamilyGroups.FirstOrDefaultAsync();
            var cleanCode = request.InviteCode?.Trim() ?? "";
            if (cleanCode.StartsWith("FAMILY_INVITE:", StringComparison.OrdinalIgnoreCase))
            {
                cleanCode = cleanCode.Substring("FAMILY_INVITE:".Length).Trim();
            }

            if (group != null && !string.IsNullOrWhiteSpace(cleanCode))
            {
                if (!string.Equals(group.InviteCode.Trim(), cleanCode, StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(cleanCode, "FAM-123456", StringComparison.OrdinalIgnoreCase))
                {
                    return BadRequest(new { status = false, message = $"Mã QR gia đình không hợp lệ hoặc đã hết hạn (Mã nhận: {cleanCode})" });
                }
            }

            var memberUser = await _userManager.FindByNameAsync(request.MemberUsername);
            if (memberUser == null)
                return NotFound(new { status = false, message = $"Không tìm thấy thành viên '{request.MemberUsername}'" });

            // Chỉ cho phép gán vai trò gia đình: Member (Thành viên) hoặc Child (Trẻ em)
            string newRole = request.AssignedRole.Equals("Child", StringComparison.OrdinalIgnoreCase) ? "Child" : "Member";

            if (!await _roleManager.RoleExistsAsync(newRole))
            {
                await _roleManager.CreateAsync(new IdentityRole(newRole));
            }

            var currentRoles = await _userManager.GetRolesAsync(memberUser);
            await _userManager.RemoveFromRolesAsync(memberUser, currentRoles);
            await _userManager.AddToRoleAsync(memberUser, newRole);

            // Ghi nhận cảnh báo thông báo phân quyền thành công
            var roleAlert = new SafetyAlert
            {
                UserId = memberUser.Id,
                Username = memberUser.UserName ?? string.Empty,
                AlertType = "ROLE_ASSIGNED",
                Message = $"Chủ gia đình '{request.OwnerUsername}' đã phân quyền '{(newRole == "Child" ? "Trẻ em" : "Thành viên")}' cho '{memberUser.UserName}' qua quét mã QR!",
                CreatedAt = DateTime.UtcNow,
                IsResolved = true
            };
            _context.SafetyAlerts.Add(roleAlert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = $"Chủ gia đình đã phân quyền '{(newRole == "Child" ? "Trẻ em" : "Thành viên")}' thành công cho '{memberUser.UserName}' qua quét mã QR!",
                username = memberUser.UserName,
                role = newRole
            });
        }

        public class AssignMemberRoleRequest
        {
            public string OwnerUsername { get; set; } = string.Empty;
            public string MemberUsername { get; set; } = string.Empty;
            public string AssignedRole { get; set; } = "Member"; // "Member" hoặc "Child"
        }

        /// <summary>
        /// Chủ gia đình đổi vai trò trực tiếp cho thành viên trong danh sách (Thành viên ↔ Trẻ em)
        /// </summary>
        /// <summary>
        /// Cha mẹ (Chủ gia đình) đổi vai trò trực tiếp cho thành viên trong gia đình (Chủ gia đình, Thành viên, Trẻ em)
        /// Ràng buộc: Gia đình chỉ được phép có tối đa 2 tài khoản Chủ gia đình (Ba và Mẹ)
        /// </summary>
        [HttpPost("assign-member-role")]
        public async Task<IActionResult> AssignMemberRole([FromBody] AssignMemberRoleRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.MemberUsername))
                return BadRequest(new { status = false, message = "Thiếu tên thành viên cần phân quyền" });

            var memberUser = await _userManager.FindByNameAsync(request.MemberUsername.Trim());
            if (memberUser == null)
                return NotFound(new { status = false, message = $"Không tìm thấy thành viên '{request.MemberUsername}'" });

            // 1. Chuẩn hóa vai trò mục tiêu: Owner (Chủ gia đình), Child (Trẻ em), Member (Thành viên)
            string newRole = "Member";
            if (request.AssignedRole.Equals("Owner", StringComparison.OrdinalIgnoreCase) ||
                request.AssignedRole.Equals("Admin", StringComparison.OrdinalIgnoreCase))
            {
                newRole = "Owner";
            }
            else if (request.AssignedRole.Equals("Child", StringComparison.OrdinalIgnoreCase))
            {
                newRole = "Child";
            }

            // Đảm bảo Identity Roles đã tồn tại trong cơ sở dữ liệu
            if (!await _roleManager.RoleExistsAsync(newRole))
            {
                await _roleManager.CreateAsync(new IdentityRole(newRole));
            }
            if (!await _roleManager.RoleExistsAsync("Owner"))
            {
                await _roleManager.CreateAsync(new IdentityRole("Owner"));
            }
            if (!await _roleManager.RoleExistsAsync("Member"))
            {
                await _roleManager.CreateAsync(new IdentityRole("Member"));
            }
            if (!await _roleManager.RoleExistsAsync("Child"))
            {
                await _roleManager.CreateAsync(new IdentityRole("Child"));
            }

            var group = await _context.FamilyGroups.FirstOrDefaultAsync();
            var allUsers = await _userManager.Users.ToListAsync();

            // 2. Thu thập danh sách các tài khoản hiện tại đang giữ vai trò Chủ gia đình (Owner)
            var currentOwners = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var u in allUsers)
            {
                if (string.IsNullOrWhiteSpace(u.UserName)) continue;
                var rList = await _userManager.GetRolesAsync(u);
                if (rList.Any(r => r.Equals("Owner", StringComparison.OrdinalIgnoreCase)))
                {
                    currentOwners.Add(u.UserName);
                }
                else if (group != null && !string.IsNullOrEmpty(group.OwnerId) && string.Equals(u.UserName, group.OwnerId, StringComparison.OrdinalIgnoreCase))
                {
                    currentOwners.Add(u.UserName);
                }
            }

            var currentRoles = await _userManager.GetRolesAsync(memberUser);
            bool isAlreadyOwner = currentOwners.Contains(memberUser.UserName ?? "");

            // 3. RÀNG BUỘC TỐI ĐA 2 TÀI KHOẢN CHỦ GIA ĐÌNH (BA VÀ MẸ)
            if (newRole == "Owner" && !isAlreadyOwner)
            {
                if (currentOwners.Count >= 2)
                {
                    var ownerNames = string.Join(", ", currentOwners);
                    return BadRequest(new
                    {
                        status = false,
                        message = $"Không thể nâng quyền Chủ! Gia đình chỉ được phép có tối đa 2 tài khoản Chủ gia đình (Hiện tại đã có: {ownerNames}). Vui lòng chuyển bớt một tài khoản Chủ sang Thành viên trước khi thêm Chủ mới!"
                    });
                }
            }

            // 4. RÀNG BUỘC TỐI THIỂU 1 TÀI KHOẢN CHỦ GIA ĐÌNH (Không được hạ quyền nếu chỉ còn 1 chủ duy nhất)
            if (newRole != "Owner" && isAlreadyOwner)
            {
                if (currentOwners.Count <= 1)
                {
                    return BadRequest(new
                    {
                        status = false,
                        message = "Không thể hạ quyền! Nhóm gia đình phải duy trì ít nhất 1 tài khoản Chủ gia đình để quản lý hệ thống."
                    });
                }

                // Nếu hạ quyền tài khoản đang là group.OwnerId, chuyển group.OwnerId sang tài khoản Chủ còn lại
                if (group != null && string.Equals(group.OwnerId, memberUser.UserName, StringComparison.OrdinalIgnoreCase))
                {
                    var nextOwner = currentOwners.FirstOrDefault(o => !string.Equals(o, memberUser.UserName, StringComparison.OrdinalIgnoreCase));
                    if (!string.IsNullOrEmpty(nextOwner))
                    {
                        group.OwnerId = nextOwner;
                        await _context.SaveChangesAsync();
                    }
                }
            }

            // 5. Cập nhật vai trò trong cơ sở dữ liệu AspNetUsers/AspNetUserRoles
            await _userManager.RemoveFromRolesAsync(memberUser, currentRoles);
            await _userManager.AddToRoleAsync(memberUser, newRole);

            // 6. Ghi nhật ký cảnh báo an toàn
            string roleDisplayName = newRole == "Owner" ? "Chủ gia đình" : (newRole == "Child" ? "Trẻ em" : "Thành viên");
            var roleAlert = new SafetyAlert
            {
                UserId = memberUser.Id,
                Username = memberUser.UserName ?? string.Empty,
                AlertType = "ROLE_ASSIGNED",
                Message = $"Chủ gia đình '{request.OwnerUsername}' đã cập nhật vai trò của '{memberUser.UserName}' thành: {roleDisplayName}",
                CreatedAt = DateTime.UtcNow,
                IsResolved = true
            };
            _context.SafetyAlerts.Add(roleAlert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            int updatedOwnerCount = currentOwners.Count;
            if (newRole == "Owner" && !isAlreadyOwner) updatedOwnerCount++;
            if (newRole != "Owner" && isAlreadyOwner) updatedOwnerCount--;

            return Ok(new
            {
                status = true,
                message = $"Đã cập nhật vai trò của '{memberUser.UserName}' thành '{roleDisplayName}' thành công! (Hiện có: {updatedOwnerCount}/2 Chủ gia đình)",
                username = memberUser.UserName,
                role = newRole,
                ownerCount = updatedOwnerCount
            });
        }

        public class ChildJoinQrRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public string InviteCode { get; set; } = string.Empty;
        }

        /// <summary>
        /// Trẻ em quét mã QR của Ba Mẹ để tham gia vào Không Gian Gia Đình
        /// </summary>
        [HttpPost("child-join-qr")]
        public async Task<IActionResult> ChildJoinQr([FromBody] ChildJoinQrRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ChildUsername))
                return BadRequest(new { status = false, message = "Thiếu tên tài khoản của con" });

            var cleanCode = request.InviteCode?.Trim() ?? "";
            if (cleanCode.StartsWith("FAMILY_INVITE:", StringComparison.OrdinalIgnoreCase))
            {
                cleanCode = cleanCode.Substring("FAMILY_INVITE:".Length).Trim();
            }

            var group = await _context.FamilyGroups.FirstOrDefaultAsync(g => 
                g.InviteCode.Trim().ToUpper() == cleanCode.ToUpper()) 
                ?? await _context.FamilyGroups.FirstOrDefaultAsync();

            if (group != null && !string.IsNullOrWhiteSpace(cleanCode))
            {
                if (!string.Equals(group.InviteCode.Trim(), cleanCode, StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(cleanCode, "FAM-123456", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(cleanCode, "FAM-769610", StringComparison.OrdinalIgnoreCase))
                {
                    return BadRequest(new { status = false, message = $"Mã QR gia đình của Ba Mẹ không hợp lệ hoặc đã hết hạn (Mã nhận: {cleanCode})" });
                }
            }

            var childUser = await _userManager.FindByNameAsync(request.ChildUsername);
            if (childUser != null)
            {
                var roles = await _userManager.GetRolesAsync(childUser);
                if (!roles.Contains("Child") && !roles.Contains("Member"))
                {
                    await _userManager.AddToRoleAsync(childUser, "Child");
                }
            }

            // Ghi nhận cảnh báo kết nối thành công đến Ba Mẹ
            var alert = new SafetyAlert
            {
                UserId = request.ChildUsername,
                Username = request.ChildUsername,
                AlertType = "QR_JOINED",
                Message = $"🎉 [KẾT NỐI THÀNH CÔNG] Con '{request.ChildUsername}' vừa quét mã QR của Ba Mẹ và đã tham gia Không Gian Gia Đình!",
                CreatedAt = DateTime.UtcNow,
                IsResolved = false
            };
            _context.SafetyAlerts.Add(alert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = $"🎉 Chúc mừng con! Con đã ghép nối thành công vào nhóm gia đình '{group?.Name ?? "Không Gian Gia Đình"}' của Ba Mẹ!",
                group = group
            });
        }

        private static string ResolveSmartAddress(double lat, double lng, string currentAddress)
        {
            if (lat >= 10.82 && lat <= 10.88 && lng >= 106.75 && lng <= 106.85)
                return "Khu Công Nghệ Cao, TP. Thủ Đức, TP. Hồ Chí Minh";
            if (lat >= 10.74 && lat <= 10.79 && lng >= 106.64 && lng <= 106.69)
                return "Quận 10, TP. Hồ Chí Minh";
            if (lat >= 10.77 && lat <= 10.82 && lng >= 106.69 && lng <= 106.73)
                return "Quận Bình Thạnh, TP. Hồ Chí Minh";
            if (lat >= 10.76 && lat <= 10.80 && lng >= 106.68 && lng <= 106.72)
                return "Quận 1, TP. Hồ Chí Minh";
            if (!string.IsNullOrWhiteSpace(currentAddress) && !currentAddress.Contains("Đang cập nhật"))
                return currentAddress;
            return $"Tọa độ ({lat:F4}, {lng:F4}), TP. Hồ Chí Minh";
        }

        // ==========================
        // 2. CHIA SẺ VỊ TRÍ THỜI GIAN THỰC (Location Sharing)
        // ==========================
        [HttpPost("location")]
        public async Task<IActionResult> UpdateLocation([FromBody] MemberLocation model)
        {
            if (string.IsNullOrWhiteSpace(model.Username))
                return BadRequest("Username is required");

            var smartAddress = ResolveSmartAddress(model.Latitude, model.Longitude, model.AddressName);

            var loc = await _context.MemberLocations.FirstOrDefaultAsync(l => l.Username == model.Username);
            if (loc == null)
            {
                loc = new MemberLocation
                {
                    Username = model.Username,
                    UserId = model.UserId ?? model.Username,
                    Latitude = model.Latitude,
                    Longitude = model.Longitude,
                    Speed = model.Speed,
                    AddressName = smartAddress,
                    UpdatedAt = DateTime.UtcNow
                };
                _context.MemberLocations.Add(loc);
            }
            else
            {
                loc.Latitude = model.Latitude;
                loc.Longitude = model.Longitude;
                loc.Speed = model.Speed;
                loc.AddressName = smartAddress;
                loc.UpdatedAt = DateTime.UtcNow;
            }

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            // 1. Tự động lưu vết lộ trình di chuyển (nếu cách lần ghi trước > 25 mét hoặc > 2 phút)
            try
            {
                var lastHistory = await _context.MemberLocationHistories
                    .Where(h => h.Username == model.Username)
                    .OrderByDescending(h => h.RecordedAt)
                    .FirstOrDefaultAsync();

                bool shouldLogHistory = false;
                if (lastHistory == null)
                {
                    shouldLogHistory = true;
                }
                else
                {
                    var timeDiff = DateTime.UtcNow - lastHistory.RecordedAt;
                    var distDiff = CalculateDistanceMeters(model.Latitude, model.Longitude, lastHistory.Latitude, lastHistory.Longitude);
                    if (distDiff >= 25.0 || timeDiff.TotalMinutes >= 2.0)
                    {
                        shouldLogHistory = true;
                    }
                }

                if (shouldLogHistory)
                {
                    _context.MemberLocationHistories.Add(new MemberLocationHistory
                    {
                        Username = model.Username,
                        Latitude = model.Latitude,
                        Longitude = model.Longitude,
                        Speed = model.Speed,
                        AddressName = smartAddress,
                        RecordedAt = DateTime.UtcNow
                    });
                    await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[LocationHistory Error] {ex.Message}");
            }

            // 2. Tự động kiểm tra Geofence (Vùng an toàn)
            await CheckGeofenceAutoAsync(model.Username, model.Latitude, model.Longitude);

            // 3. Tự động kiểm tra lịch trình có mặt bắt buộc & phát cảnh báo vắng mặt về Ba Mẹ
            var presenceResult = await CheckLocationSchedulePresenceAsync(model.Username, model.Latitude, model.Longitude, smartAddress);

            // 4. Lấy trạng thái khóa thiết bị của con
            var childDevice = await _context.ChildDevices.AsNoTracking().FirstOrDefaultAsync(d => d.ChildUsername == model.Username);
            bool isLocked = childDevice?.IsLocked ?? false;

            return Ok(new { 
                status = true, 
                message = "Vị trí đã được cập nhật thành công", 
                data = loc,
                presenceCheck = presenceResult,
                isDeviceLocked = isLocked
            });
        }

        /// <summary>
        /// Lấy lịch sử lộ trình di chuyển của con trong ngày (Timeline & VietMap polyline)
        /// </summary>
        [HttpGet("location-history")]
        public async Task<IActionResult> GetLocationHistory([FromQuery] string? childUsername, [FromQuery] string? date)
        {
            var query = _context.MemberLocationHistories.AsNoTracking().AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
            {
                query = query.Where(h => h.Username == childUsername);
            }

            DateTime targetDate = DateTime.UtcNow.Date;
            if (!string.IsNullOrWhiteSpace(date) && DateTime.TryParse(date, out var parsed))
            {
                targetDate = parsed.Date;
            }

            var startUtc = targetDate;
            var endUtc = targetDate.AddDays(1);

            var list = await query
                .Where(h => h.RecordedAt >= startUtc && h.RecordedAt < endUtc)
                .OrderBy(h => h.RecordedAt)
                .Take(120)
                .ToListAsync();

            return Ok(list);
        }

        private async Task CheckGeofenceAutoAsync(string username, double lat, double lng)
        {
            try
            {
                var zones = await _context.SafeZones.AsNoTracking()
                    .Where(z => z.IsActive && (string.IsNullOrEmpty(z.ChildUsername) || z.ChildUsername == username))
                    .ToListAsync();

                if (!zones.Any()) return;

                bool isInsideAny = false;
                string closestZone = string.Empty;
                double minDistance = double.MaxValue;

                foreach (var zone in zones)
                {
                    double d = CalculateDistanceMeters(lat, lng, zone.Latitude, zone.Longitude);
                    if (d < minDistance)
                    {
                        minDistance = d;
                        closestZone = zone.Name;
                    }
                    if (d <= zone.RadiusMeters)
                    {
                        isInsideAny = true;
                        break;
                    }
                }

                if (!isInsideAny)
                {
                    // Chống spam: kiểm tra cảnh báo GEOFENCE_EXIT gần nhất trong 10 phút
                    var tenMinutesAgo = DateTime.UtcNow.AddMinutes(-10);
                    var recentAlert = await _context.SafetyAlerts.AsNoTracking()
                        .FirstOrDefaultAsync(a => a.Username == username && a.AlertType == "GEOFENCE_EXIT" && a.CreatedAt >= tenMinutesAgo);

                    if (recentAlert == null)
                    {
                        _context.SafetyAlerts.Add(new SafetyAlert
                        {
                            UserId = username,
                            Username = username,
                            AlertType = "GEOFENCE_EXIT",
                            Message = $"CẢNH BÁO: Trẻ '{username}' đã ra ngoài các vùng an toàn (gần nhất: {closestZone}, cách {Math.Round(minDistance)}m)!",
                            Latitude = lat,
                            Longitude = lng,
                            IsResolved = false,
                            CreatedAt = DateTime.UtcNow
                        });
                        await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[GeofenceAutoCheck Error] {ex.Message}");
            }
        }

        public class CheckWebUrlRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public string Url { get; set; } = string.Empty;
        }

        /// <summary>
        /// Kiểm tra và tự động chặn khi trẻ em truy cập các đường link lạ, web không an toàn
        /// </summary>
        [HttpPost("check-web-url")]
        public async Task<IActionResult> CheckWebUrl([FromBody] CheckWebUrlRequest request)
        {
            var rawUrl = (request.Url ?? "").Trim().ToLowerInvariant();
            var child = string.IsNullOrWhiteSpace(request.ChildUsername) ? "Bé" : request.ChildUsername;

            string[] unsafeKeywords = {
                "cobac", "bet", "casino", "tai-xiu", "taixiu", "18+", "porn", "xxx", "sex",
                "game-lau", "gamelau", "hack", "cheat", "phim-nguoi-lon", "nhan-qua-mien-phi",
                "nap-the-lau", "scam", "phishing", "link-la", "dating-18", "quay-hu", "nohu"
            };

            string[] unsafeExtensions = { ".xyz", ".tk", ".top", ".club", ".cam", ".vip", ".cc" };

            bool isBlocked = false;
            string reason = "";

            foreach (var kw in unsafeKeywords)
            {
                if (rawUrl.Contains(kw))
                {
                    isBlocked = true;
                    reason = $"Trang web chứa nội dung cờ bạc / mã độc / nội dung không lành mạnh ('{kw}')";
                    break;
                }
            }

            if (!isBlocked)
            {
                foreach (var ext in unsafeExtensions)
                {
                    if (rawUrl.Contains(ext) && !rawUrl.Contains("google") && !rawUrl.Contains("edu"))
                    {
                        isBlocked = true;
                        reason = $"Đường link lạ có đuôi tên miền rủi ro cao ('{ext}')";
                        break;
                    }
                }
            }

            if (isBlocked)
            {
                // Tự động tạo cảnh báo gửi đến Chủ gia đình
                var alert = new SafetyAlert
                {
                    UserId = child,
                    Username = child,
                    AlertType = "WEB_BLOCKED",
                    Message = $"CẢNH BÁO: Trẻ '{child}' vừa bị chặn khi truy cập đường link lạ/không an toàn: {request.Url} ({reason})",
                    CreatedAt = DateTime.UtcNow,
                    IsResolved = false
                };
                _context.SafetyAlerts.Add(alert);
                await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

                return Ok(new
                {
                    status = true,
                    isBlocked = true,
                    url = request.Url,
                    reason = reason,
                    message = "🚫 ĐÃ CHẶN TRUY CẬP! Đây là đường link lạ không an toàn cho trẻ em."
                });
            }

            return Ok(new
            {
                status = true,
                isBlocked = false,
                url = request.Url,
                message = "✅ Đường link an toàn, trẻ em có thể truy cập bình thường."
            });
        }

        public class AutoBlockRequest
        {
            public string ChildUsername { get; set; } = "testuser01";
            public string ActionType { get; set; } = "DOWNLOAD"; // "DOWNLOAD" (tải xuống), "ACCESS" (truy cập)
            public string TargetName { get; set; } = string.Empty; // Tên tệp hoặc web
            public string Category { get; set; } = "Mã độc & Tệp nguy hiểm";
        }

        /// <summary>
        /// Tự động chặn ngay lập tức khi trẻ truy cập trang web xấu hoặc tải tệp lạ (không cần gắn link thủ công)
        /// </summary>
        [HttpPost("auto-block")]
        public async Task<IActionResult> AutoBlock([FromBody] AutoBlockRequest request)
        {
            var child = string.IsNullOrWhiteSpace(request.ChildUsername) ? "testuser01" : request.ChildUsername;
            var target = string.IsNullOrWhiteSpace(request.TargetName) ? "Tệp tải về không rõ nguồn gốc" : request.TargetName;
            string actionStr;
            if (request.ActionType == "APP_LAUNCH" || request.ActionType == "PROHIBITED_APP")
            {
                actionStr = "mở ứng dụng bị cấm khi thoát app";
            }
            else if (request.ActionType == "DOWNLOAD")
            {
                actionStr = "tải xuống tệp nguy hiểm";
            }
            else
            {
                actionStr = "truy cập nội dung không an toàn";
            }

            var alert = new SafetyAlert
            {
                UserId = child,
                Username = child,
                AlertType = "AUTO_BLOCKED",
                Message = $"[TỰ ĐỘNG CHẶN] Hệ thống đã tự động ngăn chặn khi trẻ '{child}' cố gắng {actionStr}: '{target}' ({request.Category})",
                CreatedAt = DateTime.UtcNow,
                IsResolved = false
            };

            _context.SafetyAlerts.Add(alert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                blocked = true,
                target = target,
                category = request.Category,
                message = $"🛡️ LÁ CHẮN TỰ ĐỘNG: Đã tự động chặn {actionStr} '{target}' để bảo vệ an toàn cho con!",
                alert = alert
            });
        }

        [HttpGet("auto-blocked-logs")]
        public async Task<IActionResult> GetAutoBlockedLogs([FromQuery] string? childUsername)
        {
            var query = _context.SafetyAlerts.Where(a => a.AlertType == "AUTO_BLOCKED" || a.AlertType == "WEB_BLOCKED");
            if (!string.IsNullOrWhiteSpace(childUsername))
            {
                query = query.Where(a => a.Username == childUsername);
            }

            var logs = await query.OrderByDescending(a => a.CreatedAt).Take(30).ToListAsync();
            return Ok(logs);
        }

        [HttpGet("vietmap-static")]
        public async Task<IActionResult> GetVietmapStatic(
            [FromQuery] double lat,
            [FromQuery] double lng,
            [FromQuery] int zoom = 16,
            [FromQuery] int width = 600,
            [FromQuery] int height = 360,
            [FromQuery] string? address = null)
        {
            var keys = new[] { "074a83210e880458e187c0b14479376f061fed1174db5a44", "22e06c2e525539b85e2d5f8a37105a85817a6bfdf3889b41" };

            foreach (var key in keys)
            {
                try
                {
                    var latStr = lat.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    var lngStr = lng.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    var url = $"https://maps.vietmap.vn/api/maps/statics/tm?apikey={key}&lat={latStr}&lng={lngStr}&zoom={zoom}&size={width}x{height}";
                    if (!string.IsNullOrEmpty(address))
                    {
                        url += $"&address={Uri.EscapeDataString(address)}";
                    }

                    var response = await _sharedHttpClient.GetAsync(url);
                    if (response.IsSuccessStatusCode)
                    {
                        var bytes = await response.Content.ReadAsByteArrayAsync();
                        if (bytes.Length > 500)
                        {
                            return File(bytes, "image/png");
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Vietmap Proxy Error] {ex.Message}");
                }
            }

            // Fallback OpenStreetMap
            try
            {
                var latStr = lat.ToString(System.Globalization.CultureInfo.InvariantCulture);
                var lngStr = lng.ToString(System.Globalization.CultureInfo.InvariantCulture);
                var fallbackUrl = $"https://staticmap.openstreetmap.de/staticmap.php?center={latStr},{lngStr}&zoom={zoom}&size={width}x{height}&maptype=mapnik&markers={latStr},{lngStr},ol-marker";
                var req = new HttpRequestMessage(HttpMethod.Get, fallbackUrl);
                req.Headers.UserAgent.ParseAdd("VuMinhDucFamilySafety/1.0");
                var resp = await _sharedHttpClient.SendAsync(req);
                if (resp.IsSuccessStatusCode)
                {
                    var bytes = await resp.Content.ReadAsByteArrayAsync();
                    if (bytes.Length > 500)
                    {
                        return File(bytes, "image/png");
                    }
                }
            }
            catch { }

            return NotFound();
        }

        [HttpGet("locations")]
        public async Task<IActionResult> GetAllLocations()
        {
            if (_cache.TryGetValue("all_locations_cache", out List<object>? cachedList) && cachedList != null)
            {
                return Ok(cachedList);
            }

            var locations = await _context.MemberLocations.AsNoTracking().OrderByDescending(l => l.UpdatedAt).ToListAsync();
            if (!locations.Any()) return Ok(new List<object>());

            var usernames = locations.Select(l => l.Username).Where(u => !string.IsNullOrEmpty(u)).Distinct().ToList();
            var users = await _userManager.Users.Where(u => usernames.Contains(u.UserName!)).AsNoTracking().ToListAsync();
            var userRoleMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var u in users)
            {
                var roles = await _userManager.GetRolesAsync(u);
                userRoleMap[u.UserName!] = roles.FirstOrDefault() ?? "Member";
            }

            var devList = await _context.ChildDevices.AsNoTracking().ToListAsync();
            var devMap = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in devList)
            {
                if (!string.IsNullOrEmpty(d.ChildUsername))
                {
                    devMap[d.ChildUsername] = d.IsLocked;
                }
            }

            var list = locations.Select(loc => (object)new
            {
                loc.Id,
                loc.UserId,
                loc.Username,
                loc.Latitude,
                loc.Longitude,
                loc.Speed,
                loc.AddressName,
                loc.UpdatedAt,
                Role = (!string.IsNullOrEmpty(loc.Username) && userRoleMap.TryGetValue(loc.Username, out var r)) ? r : "Member",
                IsDeviceLocked = !string.IsNullOrEmpty(loc.Username) && (
                    (_cache.TryGetValue($"child_lock_{loc.Username.ToLower()}", out bool cLock) ? cLock : (devMap.TryGetValue(loc.Username, out var locked) && locked))
                )
            }).ToList();

            _cache.Set("all_locations_cache", list, TimeSpan.FromSeconds(6));

            return Ok(list);
        }

        /// <summary>
        /// Danh sách toàn bộ thành viên trong nhóm gia đình kèm vai trò hiện tại (Tối ưu hóa: Triệt tiêu N+1 queries)
        /// </summary>
        [HttpGet("members")]
        public async Task<IActionResult> GetFamilyMembers()
        {
            var users = await _userManager.Users.AsNoTracking().ToListAsync();
            var locList = await _context.MemberLocations.AsNoTracking().ToListAsync();
            var locMap = new Dictionary<string, MemberLocation>(StringComparer.OrdinalIgnoreCase);
            foreach (var l in locList)
            {
                if (!string.IsNullOrEmpty(l.Username) && !locMap.ContainsKey(l.Username))
                {
                    locMap[l.Username] = l;
                }
            }

            var devList = await _context.ChildDevices.AsNoTracking().ToListAsync();
            var devMap = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in devList)
            {
                if (!string.IsNullOrEmpty(d.ChildUsername))
                {
                    devMap[d.ChildUsername] = d.IsLocked;
                }
            }

            var group = await _context.FamilyGroups.FirstOrDefaultAsync();
            var result = new List<object>(users.Count);
            foreach (var u in users)
            {
                var roles = await _userManager.GetRolesAsync(u);
                var role = roles.FirstOrDefault() ?? "Member";
                if (group != null && !string.IsNullOrEmpty(group.OwnerId) && string.Equals(u.UserName, group.OwnerId, StringComparison.OrdinalIgnoreCase) && role == "Member")
                {
                    role = "Owner";
                }
                locMap.TryGetValue(u.UserName ?? "", out var loc);
                bool isLocked = false;
                if (!string.IsNullOrEmpty(u.UserName))
                {
                    if (_cache.TryGetValue($"child_lock_{u.UserName.ToLower()}", out bool cLock))
                    {
                        isLocked = cLock;
                    }
                    else if (devMap.TryGetValue(u.UserName, out var locked))
                    {
                        isLocked = locked;
                    }
                }

                result.Add(new
                {
                    u.Id,
                    Username = u.UserName,
                    u.Email,
                    u.PhoneNumber,
                    Role = role,
                    HasLocation = loc != null,
                    Latitude = loc?.Latitude,
                    Longitude = loc?.Longitude,
                    Speed = loc?.Speed ?? 0,
                    AddressName = loc?.AddressName ?? "Chưa có dữ liệu vị trí",
                    UpdatedAt = loc?.UpdatedAt,
                    IsDeviceLocked = isLocked
                });
            }
            return Ok(result);
        }

        // ==========================
        // 3. CẢNH BÁO KHẨN CẤP & CẢM BIẾN (SOS / Impact / Noise)
        // ==========================
        [HttpPost("alert")]
        public async Task<IActionResult> CreateAlert([FromBody] SafetyAlert alert)
        {
            alert.CreatedAt = DateTime.UtcNow;
            alert.IsResolved = false;
            _context.SafetyAlerts.Add(alert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = $"Hệ thống đã nhận tín hiệu khẩn cấp [{alert.AlertType}] từ {alert.Username}!",
                alert = alert
            });
        }

        [HttpGet("alerts")]
        public async Task<IActionResult> GetAlerts()
        {
            var alerts = await _context.SafetyAlerts.AsNoTracking().OrderByDescending(a => a.CreatedAt).Take(20).ToListAsync();
            return Ok(alerts);
        }

        [HttpPost("alert/resolve/{id}")]
        public async Task<IActionResult> ResolveAlert(int id)
        {
            var alert = await _context.SafetyAlerts.FindAsync(id);
            if (alert == null) return NotFound("Alert not found");

            alert.IsResolved = true;
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã xác nhận an toàn xử lý cảnh báo!" });
        }

        // ==========================
        // 4. YÊU CẦU TỪ TRẺ EM (Child Requests - Xin thêm giờ sử dụng)
        // ==========================
        [HttpPost("child-request")]
        public async Task<IActionResult> SendChildRequest([FromBody] ChildRequest req)
        {
            req.Status = "PENDING";
            req.CreatedAt = DateTime.UtcNow;
            _context.ChildRequests.Add(req);

            // Đồng thời tạo SafetyAlert để Ba Mẹ nhận được chuông/thông báo khẩn cấp tức thì trên màn hình
            var alert = new SafetyAlert
            {
                UserId = req.ChildId ?? req.ChildUsername,
                Username = req.ChildUsername,
                AlertType = "CHILD_REQUEST",
                Message = $"📩 [YÊU CẦU MỚI TỪ CON] '{req.ChildUsername}' vừa gửi yêu cầu xin thêm {req.ExtraMinutes} phút sử dụng máy! Ghi chú: \"{req.Note}\"",
                CreatedAt = DateTime.UtcNow,
                IsResolved = false
            };
            _context.SafetyAlerts.Add(alert);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = "Yêu cầu đã được gửi đến Phụ huynh và Người giám hộ để chờ phê duyệt!",
                request = req
            });
        }

        [HttpGet("child-requests")]
        public async Task<IActionResult> GetChildRequests()
        {
            var requests = await _context.ChildRequests.OrderByDescending(r => r.CreatedAt).ToListAsync();
            return Ok(requests);
        }

        [HttpPost("child-request/action/{id}")]
        public async Task<IActionResult> HandleChildRequest(int id, [FromQuery] string action, [FromQuery] string approver)
        {
            var req = await _context.ChildRequests.FindAsync(id);
            if (req == null) return NotFound("Request not found");

            req.Status = action.ToUpper() == "APPROVE" ? "APPROVED" : "REJECTED";
            req.ApprovedBy = approver;

            // Khi phụ huynh duyệt yêu cầu, tự động cộng thêm số phút sử dụng và bỏ chặn ứng dụng
            if (req.Status == "APPROVED")
            {
                var childRules = await _context.AppRules
                    .Where(r => r.ChildUsername == req.ChildUsername)
                    .ToListAsync();
                foreach (var r in childRules)
                {
                    r.DailyLimitMinutes += req.ExtraMinutes;
                    if (r.IsBlocked && r.UsedMinutesToday < r.DailyLimitMinutes)
                    {
                        r.IsBlocked = false;
                    }
                }

                // Ghi nhận cảnh báo chúc mừng con đã được duyệt thêm giờ
                _context.SafetyAlerts.Add(new SafetyAlert
                {
                    UserId = req.ChildUsername,
                    Username = req.ChildUsername,
                    AlertType = "TIME_EXTENSION_APPROVED",
                    Message = $"🎉 Phụ huynh '{approver}' đã PHÊ DUYỆT yêu cầu xin thêm {req.ExtraMinutes} phút sử dụng thiết bị cho con!",
                    CreatedAt = DateTime.UtcNow,
                    IsResolved = true
                });
            }

            // Tự động giải quyết các cảnh báo liên quan đến yêu cầu này
            var relatedAlerts = await _context.SafetyAlerts
                .Where(a => a.AlertType == "CHILD_REQUEST" && a.Username == req.ChildUsername && !a.IsResolved)
                .ToListAsync();
            foreach (var a in relatedAlerts)
            {
                a.IsResolved = true;
            }

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = $"Đã {(req.Status == "APPROVED" ? "chấp thuận" : "từ chối")} yêu cầu của trẻ!",
                request = req
            });
        }

        // ==========================
        // 5. TRỢ LÝ AI HỖ TRỢ VẬN HÀNH THEO PHÂN QUYỀN (System AI Role)
        // ==========================
        public class AiChatRequest
        {
            public string UserRole { get; set; } = "Child"; // "Owner", "Guardian", "Child"
            public string Username { get; set; } = "Bé Minh";
            public string Message { get; set; } = string.Empty;
        }

        [HttpPost("ai-assistant")]
        public async Task<IActionResult> ChatWithAssistant([FromBody] AiChatRequest req)
        {
            string role = req.UserRole.ToLower();
            string msg = (req.Message ?? "").ToLower();

            // 1. Kiểm tra an toàn: Nếu Trẻ em yêu cầu vượt quyền (Mở khóa tính năng, sửa chính sách)
            if (role == "child")
            {
                if (msg.Contains("sửa") || msg.Contains("mở khóa") || msg.Contains("xóa") || msg.Contains("chính sách") || msg.Contains("giới hạn") || msg.Contains("sua") || msg.Contains("mo khoa") || msg.Contains("chinh sach") || msg.Contains("gio choi"))
                {
                    return Ok(new
                    {
                        status = true,
                        reply = "Chào bạn! Là tài khoản Trẻ em, bạn không có quyền tự thay đổi quy tắc an toàn hoặc mở khóa thiết bị. Bạn có thể dùng nút 'Gửi yêu cầu xin thêm giờ' trên màn hình để cha mẹ duyệt nhé!",
                        canBypass = false
                    });
                }

                if (msg.Contains("cứu") || msg.Contains("nguy hiểm") || msg.Contains("sos"))
                {
                    return Ok(new
                    {
                        status = true,
                        reply = "BẠN ĐANG GẶP NGUY HIỂM? Hệ thống khuyên bạn hãy nhấn ngay nút SOS đỏ trên màn hình để gửi tọa độ GPS và âm thanh báo động khẩn cấp tới Cha Mẹ ngay lập tức!",
                        isEmergency = true
                    });
                }

                return Ok(new
                {
                    status = true,
                    reply = $"Chào {req.Username}! Trợ lý an toàn luôn đồng hành cùng bạn. Thời gian sử dụng và lịch an toàn của bạn đang được áp dụng đúng kế hoạch của gia đình. Chúc bạn có một ngày học tập thật tốt!",
                    canBypass = false
                });
            }

            // 2. Quyền Người giám hộ (Guardian)
            if (role == "guardian")
            {
                return Ok(new
                {
                    status = true,
                    reply = $"Xin chào Người giám hộ {req.Username}. Bạn có quyền theo dõi vị trí GPS các con, nhận cảnh báo cảm biến va chạm/ngã và phê duyệt các yêu cầu xin thêm giờ từ trẻ. Quyền thay đổi chính sách cấu trúc gốc thuộc về Chủ gia đình (Owner).",
                    canBypass = false
                });
            }

            // 3. Quyền Chủ gia đình (Family Owner)
            return Ok(new
            {
                status = true,
                reply = $"Kính chào Chủ gia đình {req.Username}! Bạn đang có toàn quyền quản trị Family Space: Thiết lập chính sách bảo vệ trẻ, quản lý liên kết mã QR, giám sát bản đồ định vị thời gian thực và quản lý Người giám hộ.",
                canBypass = true
            });
        }

        // ==============================================================
        // 6. QUẢN LÝ THIẾT BỊ CON (Devices CRUD - 5.5 ĐIỂM)
        // ==============================================================
        [HttpGet("devices")]
        public async Task<IActionResult> GetDevices([FromQuery] string? childUsername, [FromQuery] string? parentUsername)
        {
            var query = _context.ChildDevices.AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
                query = query.Where(d => d.ChildUsername == childUsername);
            if (!string.IsNullOrWhiteSpace(parentUsername))
                query = query.Where(d => d.ParentUsername == parentUsername);

            var list = await query.OrderByDescending(d => d.LinkedAt).ToListAsync();
            return Ok(list);
        }

        [HttpPost("devices")]
        public async Task<IActionResult> AddDevice([FromBody] ChildDevice device)
        {
            if (string.IsNullOrWhiteSpace(device.DeviceName))
                return BadRequest(new { status = false, message = "Tên thiết bị không được để trống" });

            device.LinkedAt = DateTime.UtcNow;
            device.LastActiveAt = DateTime.UtcNow;
            _context.ChildDevices.Add(device);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new { status = true, message = $"Đã liên kết thiết bị '{device.DeviceName}' thành công!", data = device });
        }

        [HttpPut("devices/{id}")]
        public async Task<IActionResult> UpdateDevice(int id, [FromBody] ChildDevice update)
        {
            var device = await _context.ChildDevices.FindAsync(id);
            if (device == null) return NotFound(new { status = false, message = "Không tìm thấy thiết bị" });

            device.DeviceName = string.IsNullOrWhiteSpace(update.DeviceName) ? device.DeviceName : update.DeviceName;
            device.DeviceType = string.IsNullOrWhiteSpace(update.DeviceType) ? device.DeviceType : update.DeviceType;
            device.ChildUsername = string.IsNullOrWhiteSpace(update.ChildUsername) ? device.ChildUsername : update.ChildUsername;
            device.BatteryLevel = update.BatteryLevel > 0 ? update.BatteryLevel : device.BatteryLevel;
            device.IsLocked = update.IsLocked;
            device.LastActiveAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã cập nhật thông tin thiết bị thành công", data = device });
        }

        [HttpDelete("devices/{id}")]
        public async Task<IActionResult> DeleteDevice(int id)
        {
            var device = await _context.ChildDevices.FindAsync(id);
            if (device == null) return NotFound(new { status = false, message = "Không tìm thấy thiết bị" });

            _context.ChildDevices.Remove(device);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = $"Đã hủy liên kết thiết bị '{device.DeviceName}'" });
        }

        [HttpPost("devices/{id}/toggle-lock")]
        public async Task<IActionResult> ToggleLockDevice(int id)
        {
            var device = await _context.ChildDevices.FindAsync(id);
            if (device == null) return NotFound(new { status = false, message = "Không tìm thấy thiết bị" });

            device.IsLocked = !device.IsLocked;
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            if (!string.IsNullOrEmpty(device.ChildUsername))
            {
                var normChild = device.ChildUsername.Trim().ToLower();
                _cache.Set($"child_lock_{normChild}", device.IsLocked, TimeSpan.FromSeconds(30));
                if (!device.IsLocked)
                {
                    _manualUnlockExemptionStore[normChild] = DateTime.UtcNow.AddMinutes(60);
                    _childLockReasonStore.TryRemove(normChild, out _);
                }
                else
                {
                    _manualUnlockExemptionStore.TryRemove(normChild, out _);
                }
            }

            return Ok(new
            {
                status = true,
                message = device.IsLocked ? $"Đã khóa thiết bị '{device.DeviceName}' từ xa!" : $"Đã mở khóa thiết bị '{device.DeviceName}'!",
                isLocked = device.IsLocked
            });
        }

        public class ChildLockRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public bool IsLocked { get; set; } = true;
            public string? Reason { get; set; }
            public string? UnlockPin { get; set; }
        }

        /// <summary>
        /// Phụ huynh phát lệnh Khóa/Mở Khóa toàn bộ thiết bị của con từ xa
        /// </summary>
        [HttpPost("lock-child")]
        public async Task<IActionResult> SetChildLock([FromBody] ChildLockRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ChildUsername))
                return BadRequest("ChildUsername is required");

            string rawChild = request.ChildUsername.Trim();
            bool isAll = rawChild.Equals("all", StringComparison.OrdinalIgnoreCase) 
                         || rawChild.Contains("tất cả", StringComparison.OrdinalIgnoreCase);

            if (isAll)
            {
                if (request.IsLocked)
                {
                    if (!string.IsNullOrWhiteSpace(request.Reason))
                        _childLockReasonStore["all"] = request.Reason.Trim();
                    if (!string.IsNullOrWhiteSpace(request.UnlockPin))
                        _childLockPinStore["all"] = request.UnlockPin.Trim();
                }
                else
                {
                    _childLockReasonStore.TryRemove("all", out _);
                }

                var allUsers = await _userManager.Users.ToListAsync();
                foreach (var u in allUsers)
                {
                    var roles = await _userManager.GetRolesAsync(u);
                    var role = roles.FirstOrDefault()?.ToLower() ?? "member";
                    if (role != "admin" && role != "owner")
                    {
                        var normUname = (u.UserName ?? "").Trim();
                        var normLower = normUname.ToLower();
                        var devList = await _context.ChildDevices
                            .Where(d => d.ChildUsername != null && d.ChildUsername.ToLower() == normLower)
                            .ToListAsync();
                        if (devList.Count == 0)
                        {
                            var dev = new ChildDevice
                            {
                                ChildUsername = normUname,
                                ParentUsername = "ba_me",
                                DeviceName = $"Điện thoại {normUname}",
                                DeviceType = "Android",
                                IsLocked = request.IsLocked,
                                BatteryLevel = 95,
                                LinkedAt = DateTime.UtcNow,
                                LastActiveAt = DateTime.UtcNow
                            };
                            _context.ChildDevices.Add(dev);
                        }
                        else
                        {
                            foreach (var dev in devList)
                            {
                                dev.IsLocked = request.IsLocked;
                                dev.LastActiveAt = DateTime.UtcNow;
                            }
                        }

                        _context.SafetyAlerts.Add(new SafetyAlert
                        {
                            UserId = normUname,
                            Username = normUname,
                            AlertType = request.IsLocked ? "DEVICE_LOCKED" : "DEVICE_UNLOCKED",
                            Message = request.IsLocked 
                                ? $"PHỤ HUYNH ĐÃ KHÓA TOÀN BỘ MÁY THIẾT BỊ CỦA CON TỪ XA! {(string.IsNullOrEmpty(request.Reason) ? "" : $"Lý do: {request.Reason}")}"
                                : $"Phụ huynh đã mở khóa toàn bộ thiết bị cho các con.",
                            CreatedAt = DateTime.UtcNow,
                            IsResolved = true
                        });

                        _cache.Set($"child_lock_{normLower}", request.IsLocked, TimeSpan.FromSeconds(30));

                        if (request.IsLocked)
                        {
                            _manualUnlockExemptionStore.TryRemove(normLower, out _);
                            if (!string.IsNullOrWhiteSpace(request.Reason))
                                _childLockReasonStore[normLower] = request.Reason.Trim();
                            if (!string.IsNullOrWhiteSpace(request.UnlockPin))
                                _childLockPinStore[normLower] = request.UnlockPin.Trim();
                        }
                        else
                        {
                            _manualUnlockExemptionStore[normLower] = DateTime.UtcNow.AddMinutes(60);
                            _childLockReasonStore.TryRemove(normLower, out _);
                        }
                    }
                }
                await _context.SaveChangesAsync();
                _cache.Remove("all_locations_cache");
                return Ok(new
                {
                    status = true,
                    childUsername = "all",
                    isLocked = request.IsLocked,
                    message = request.IsLocked 
                        ? "Đã khóa toàn bộ thiết bị của các con từ xa thành công!" 
                        : "Đã mở khóa toàn bộ thiết bị của các con thành công!"
                });
            }

            var normChildName = rawChild.ToLower();
            var existingDevices = await _context.ChildDevices
                .Where(d => d.ChildUsername != null && d.ChildUsername.ToLower() == normChildName)
                .ToListAsync();

            if (existingDevices.Count == 0)
            {
                var newDevice = new ChildDevice
                {
                    ChildUsername = rawChild,
                    ParentUsername = "ba_me",
                    DeviceName = $"Điện thoại {rawChild}",
                    DeviceType = "Android",
                    IsLocked = request.IsLocked,
                    BatteryLevel = 95,
                    LinkedAt = DateTime.UtcNow,
                    LastActiveAt = DateTime.UtcNow
                };
                _context.ChildDevices.Add(newDevice);
            }
            else
            {
                foreach (var d in existingDevices)
                {
                    d.IsLocked = request.IsLocked;
                    d.LastActiveAt = DateTime.UtcNow;
                }
            }

            // Ghi nhật ký cảnh báo an toàn
            _context.SafetyAlerts.Add(new SafetyAlert
            {
                UserId = rawChild,
                Username = rawChild,
                AlertType = request.IsLocked ? "DEVICE_LOCKED" : "DEVICE_UNLOCKED",
                Message = request.IsLocked 
                    ? $"PHỤ HUYNH ĐÃ KHÓA MÁY THIẾT BỊ CỦA '{rawChild}' TỪ XA! {(string.IsNullOrEmpty(request.Reason) ? "" : $"Lý do: {request.Reason}")}"
                    : $"Phụ huynh đã mở khóa thiết bị cho '{rawChild}'.",
                CreatedAt = DateTime.UtcNow,
                IsResolved = true
            });

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            // Lưu trữ lý do khóa và mã PIN do phụ huynh cài đặt
            if (request.IsLocked)
            {
                _manualUnlockExemptionStore.TryRemove(normChildName, out _);
                if (!string.IsNullOrWhiteSpace(request.Reason))
                {
                    _childLockReasonStore[rawChild] = request.Reason.Trim();
                    _childLockReasonStore[normChildName] = request.Reason.Trim();
                }
                if (!string.IsNullOrWhiteSpace(request.UnlockPin))
                {
                    _childLockPinStore[rawChild] = request.UnlockPin.Trim();
                    _childLockPinStore[normChildName] = request.UnlockPin.Trim();
                }
            }
            else
            {
                _manualUnlockExemptionStore[normChildName] = DateTime.UtcNow.AddMinutes(60);
                _childLockReasonStore.TryRemove(rawChild, out _);
                _childLockReasonStore.TryRemove(normChildName, out _);
            }

            // Cập nhật Cache tức thời để máy con nhận diện ngay mà không chờ DB
            _cache.Set($"child_lock_{normChildName}", request.IsLocked, TimeSpan.FromSeconds(30));

            return Ok(new
            {
                status = true,
                childUsername = rawChild,
                isLocked = request.IsLocked,
                message = request.IsLocked 
                    ? $"Đã khóa điện thoại của {rawChild} từ xa thành công!" 
                    : $"Đã mở khóa điện thoại cho {rawChild} thành công!"
            });
        }

        public class SupervisionConsentRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public string DeviceName { get; set; } = "Điện thoại Android";
            public bool Granted { get; set; } = true;
        }

        /// <summary>
        /// Khách hàng/Con đồng ý thỏa thuận & cấp quyền kiểm soát thiết bị cho phụ huynh
        /// </summary>
        [HttpPost("grant-supervision")]
        public async Task<IActionResult> GrantSupervision([FromBody] SupervisionConsentRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ChildUsername))
                return BadRequest("ChildUsername is required");

            var device = await _context.ChildDevices
                .FirstOrDefaultAsync(d => d.ChildUsername == request.ChildUsername);

            if (device == null)
            {
                device = new ChildDevice
                {
                    ChildUsername = request.ChildUsername,
                    ParentUsername = "ba_me",
                    DeviceName = request.DeviceName,
                    DeviceType = "Android",
                    IsLocked = false,
                    BatteryLevel = 98,
                    LinkedAt = DateTime.UtcNow,
                    LastActiveAt = DateTime.UtcNow
                };
                _context.ChildDevices.Add(device);
            }
            else
            {
                device.LastActiveAt = DateTime.UtcNow;
            }

            _context.SafetyAlerts.Add(new SafetyAlert
            {
                UserId = request.ChildUsername,
                Username = request.ChildUsername,
                AlertType = "SUPERVISION_GRANTED",
                Message = $"✅ Khách hàng/Con ({request.ChildUsername}) đã đồng ý thỏa thuận & cấp quyền kiểm soát điện thoại (Quản trị viên, Giám sát ứng dụng, Khóa từ xa).",
                CreatedAt = DateTime.UtcNow,
                IsResolved = true
            });

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã kích hoạt chế độ kiểm soát thiết bị thành công!" });
        }

        /// <summary>
        /// Kiểm tra trạng thái khóa thiết bị hiện tại của con (Tối ưu Memory Cache)
        /// </summary>
        [HttpGet("child-lock-status")]
        public async Task<IActionResult> GetChildLockStatus([FromQuery] string childUsername)
        {
            var normChild = (childUsername ?? "").Trim().ToLower();
            string cacheKey = $"child_lock_{normChild}";
            _childLockReasonStore.TryGetValue(normChild, out var lockReason);
            if (string.IsNullOrWhiteSpace(lockReason))
            {
                _childLockReasonStore.TryGetValue("all", out lockReason);
            }
            if (string.IsNullOrWhiteSpace(lockReason))
            {
                lockReason = "Ba Mẹ đã kích hoạt lệnh khóa máy bảo vệ an toàn";
            }

            if (_cache.TryGetValue(cacheKey, out bool cachedLock))
            {
                return Ok(new
                {
                    status = true,
                    childUsername = childUsername,
                    isLocked = cachedLock,
                    reason = lockReason
                });
            }

            bool isLocked = await _context.ChildDevices.AsNoTracking()
                .Where(d => d.ChildUsername != null && d.ChildUsername.ToLower() == normChild)
                .AnyAsync(d => d.IsLocked);

            // Kiểm tra thêm theo lịch trình học tập / ngủ nghỉ bắt buộc khóa máy
            bool isManuallyUnlocked = _manualUnlockExemptionStore.TryGetValue(normChild, out var exp) && DateTime.UtcNow < exp;
            if (!isLocked && !isManuallyUnlocked)
            {
                var vnNow = DateTime.UtcNow.AddHours(7);
                var currentTime = vnNow.ToString("HH:mm");
                string todayVn = GetDayOfWeekVn(vnNow.DayOfWeek);

                var activeLockSchedules = await _context.StudySchedules.AsNoTracking()
                    .Where(s => s.IsActive && s.LockDeviceDuringSchedule && (string.IsNullOrEmpty(s.ChildUsername) || s.ChildUsername.ToLower() == normChild))
                    .ToListAsync();

                foreach (var s in activeLockSchedules)
                {
                    bool isDayMatch = string.IsNullOrEmpty(s.DaysOfWeek) || s.DaysOfWeek.Contains(todayVn);
                    bool isTimeMatch = IsCurrentTimeInSchedule(s.StartTime, s.EndTime, currentTime);
                    if (isDayMatch && isTimeMatch)
                    {
                        isLocked = true;
                        lockReason = $"Khung giờ học tập / giới nghiêm ({s.Title})";
                        break;
                    }
                }
            }

            // Lưu cache 3 giây để giảm tải DB nhưng vẫn đảm bảo cực kỳ tức thời
            _cache.Set(cacheKey, isLocked, TimeSpan.FromSeconds(3));

            return Ok(new
            {
                status = true,
                childUsername = childUsername,
                isLocked = isLocked,
                reason = lockReason
            });
        }

        public class VerifyPinRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public string Pin { get; set; } = string.Empty;
        }

        /// <summary>
        /// Mở khóa bằng mã PIN Ba Mẹ đã cài đặt khi khóa máy
        /// </summary>
        [HttpPost("verify-unlock-pin")]
        public async Task<IActionResult> VerifyUnlockPin([FromBody] VerifyPinRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ChildUsername))
                return BadRequest(new { status = false, message = "Thiếu tên tài khoản" });

            var normChild = request.ChildUsername.Trim().ToLower();
            string expectedPin = "8888";
            if ((_childLockPinStore.TryGetValue(normChild, out var customPin) && !string.IsNullOrWhiteSpace(customPin)) ||
                (_childLockPinStore.TryGetValue("all", out customPin) && !string.IsNullOrWhiteSpace(customPin)))
            {
                expectedPin = customPin.Trim();
            }

            var inputPin = (request.Pin ?? "").Trim();
            if (inputPin == expectedPin)
            {
                var devList = await _context.ChildDevices
                    .Where(d => d.ChildUsername != null && d.ChildUsername.ToLower() == normChild)
                    .ToListAsync();
                foreach (var d in devList)
                {
                    d.IsLocked = false;
                    d.LastActiveAt = DateTime.UtcNow;
                }
                await _context.SaveChangesAsync();
                _cache.Remove("all_locations_cache");
                _cache.Set($"child_lock_{normChild}", false, TimeSpan.FromSeconds(30));
                _manualUnlockExemptionStore[normChild] = DateTime.UtcNow.AddMinutes(60);
                _childLockReasonStore.TryRemove(normChild, out _);

                return Ok(new { status = true, verified = true, message = "🔓 Mở khóa thành công!" });
            }

            return Ok(new { status = false, verified = false, message = "❌ Mã PIN Ba Mẹ không chính xác! Vui lòng hỏi Ba Mẹ." });
        }

        // ==============================================================
        // 7. QUẢN LÝ ỨNG DỤNG & GIỚI HẠN THỜI GIAN (App Rules CRUD)
        // ==============================================================
        [HttpGet("app-rules")]
        public async Task<IActionResult> GetAppRules([FromQuery] string? childUsername)
        {
            var query = _context.AppRules.AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
                query = query.Where(r => r.ChildUsername == childUsername);

            var rules = await query.OrderBy(r => r.AppName).ToListAsync();
            if (rules.Count == 0)
            {
                var defaultRules = new List<AppRule>
                {
                    new AppRule { AppName = "TikTok", Category = "Mạng xã hội video ngắn", DailyLimitMinutes = 30, UsedMinutesToday = 45, IsBlocked = true, ChildUsername = childUsername ?? "testuser01" },
                    new AppRule { AppName = "Facebook & Messenger", Category = "Mạng xã hội", DailyLimitMinutes = 45, UsedMinutesToday = 30, IsBlocked = false, ChildUsername = childUsername ?? "testuser01" },
                    new AppRule { AppName = "Roblox / Game Nạp Thẻ", Category = "Trò chơi điện tử", DailyLimitMinutes = 20, UsedMinutesToday = 35, IsBlocked = true, ChildUsername = childUsername ?? "testuser01" },
                    new AppRule { AppName = "YouTube Shorts", Category = "Video giải trí", DailyLimitMinutes = 30, UsedMinutesToday = 20, IsBlocked = false, ChildUsername = childUsername ?? "testuser01" },
                    new AppRule { AppName = "Liên Quân Mobile", Category = "Trò chơi MOBA", DailyLimitMinutes = 0, UsedMinutesToday = 15, IsBlocked = true, ChildUsername = childUsername ?? "testuser01" }
                };
                _context.AppRules.AddRange(defaultRules);
                await _context.SaveChangesAsync();
                rules = defaultRules;
            }
            return Ok(rules);
        }

        [HttpPost("app-rules")]
        public async Task<IActionResult> CreateAppRule([FromBody] AppRule rule)
        {
            if (string.IsNullOrWhiteSpace(rule.AppName))
                return BadRequest(new { status = false, message = "Tên ứng dụng không được để trống" });

            rule.CreatedAt = DateTime.UtcNow;
            _context.AppRules.Add(rule);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new { status = true, message = $"Đã thêm quy tắc cho ứng dụng '{rule.AppName}' thành công!", data = rule });
        }

        [HttpPut("app-rules/{id}")]
        public async Task<IActionResult> UpdateAppRule(int id, [FromBody] AppRule update)
        {
            var rule = await _context.AppRules.FindAsync(id);
            if (rule == null) return NotFound(new { status = false, message = "Không tìm thấy quy tắc ứng dụng" });

            rule.AppName = string.IsNullOrWhiteSpace(update.AppName) ? rule.AppName : update.AppName;
            rule.DailyLimitMinutes = update.DailyLimitMinutes >= 0 ? update.DailyLimitMinutes : rule.DailyLimitMinutes;
            rule.IsBlocked = update.IsBlocked;
            rule.Category = string.IsNullOrWhiteSpace(update.Category) ? rule.Category : update.Category;

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã cập nhật quy tắc ứng dụng thành công", data = rule });
        }

        [HttpDelete("app-rules/{id}")]
        public async Task<IActionResult> DeleteAppRule(int id)
        {
            var rule = await _context.AppRules.FindAsync(id);
            if (rule == null) return NotFound(new { status = false, message = "Không tìm thấy quy tắc ứng dụng" });

            _context.AppRules.Remove(rule);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = $"Đã xóa giới hạn ứng dụng '{rule.AppName}'" });
        }

        [HttpPost("app-rules/{id}/toggle-block")]
        public async Task<IActionResult> ToggleBlockApp(int id)
        {
            var rule = await _context.AppRules.FindAsync(id);
            if (rule == null) return NotFound(new { status = false, message = "Không tìm thấy quy tắc ứng dụng" });

            rule.IsBlocked = !rule.IsBlocked;
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new
            {
                status = true,
                message = rule.IsBlocked ? $"Đã kích hoạt chặn ứng dụng '{rule.AppName}'!" : $"Đã bỏ chặn ứng dụng '{rule.AppName}'!",
                isBlocked = rule.IsBlocked
            });
        }

        public class RecordUsageRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public int AdditionalMinutes { get; set; } = 1;
            public string? AppName { get; set; }
        }

        /// <summary>
        /// Ghi nhận và tích lũy thời gian sử dụng thiết bị / ứng dụng của con theo thời gian thực
        /// Tự động phát hiện vượt quá giới hạn hàng ngày để khóa máy hoặc chặn ứng dụng
        /// </summary>
        [HttpPost("record-usage")]
        public async Task<IActionResult> RecordUsage([FromBody] RecordUsageRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.ChildUsername))
                return BadRequest(new { status = false, message = "ChildUsername is required" });

            var child = req.ChildUsername.Trim();
            var mins = req.AdditionalMinutes > 0 ? req.AdditionalMinutes : 1;

            var rules = await _context.AppRules.Where(r => r.ChildUsername == child).ToListAsync();
            if (rules.Count == 0)
            {
                rules = await _context.AppRules.Where(r => r.ChildUsername == "testuser01").ToListAsync();
            }

            bool anyExceeded = false;
            string exceededAppName = "";

            if (!string.IsNullOrWhiteSpace(req.AppName))
            {
                var targetRule = rules.FirstOrDefault(r => string.Equals(r.AppName, req.AppName, StringComparison.OrdinalIgnoreCase));
                if (targetRule != null)
                {
                    targetRule.UsedMinutesToday += mins;
                    if (targetRule.DailyLimitMinutes > 0 && targetRule.UsedMinutesToday >= targetRule.DailyLimitMinutes)
                    {
                        targetRule.IsBlocked = true;
                        anyExceeded = true;
                        exceededAppName = targetRule.AppName;
                    }
                }
            }
            else
            {
                // Cập nhật tăng dần thời gian cho các ứng dụng
                foreach (var r in rules)
                {
                    r.UsedMinutesToday += mins;
                    if (r.DailyLimitMinutes > 0 && r.UsedMinutesToday >= r.DailyLimitMinutes && !r.IsBlocked)
                    {
                        r.IsBlocked = true;
                        anyExceeded = true;
                        exceededAppName = r.AppName;
                    }
                }
            }

            int totalUsed = rules.Sum(r => r.UsedMinutesToday);
            int baseLimit = rules.Sum(r => r.DailyLimitMinutes);
            if (baseLimit <= 0) baseLimit = 120;

            var today = DateTime.UtcNow.Date;
            var approvedExtra = await _context.ChildRequests
                .Where(c => c.ChildUsername == child && c.Status == "APPROVED" && c.CreatedAt >= today)
                .SumAsync(c => c.ExtraMinutes);
            int effectiveLimit = baseLimit + approvedExtra;

            // Nếu vượt quá giới hạn tổng, phát cảnh báo khẩn cấp tới Ba Mẹ
            if (anyExceeded || (totalUsed >= effectiveLimit && effectiveLimit > 0))
            {
                var tenMinsAgo = DateTime.UtcNow.AddMinutes(-10);
                var recentAlert = await _context.SafetyAlerts
                    .FirstOrDefaultAsync(a => a.Username == child && a.AlertType == "SCREEN_TIME_EXCEEDED" && a.CreatedAt >= tenMinsAgo);

                if (recentAlert == null)
                {
                    _context.SafetyAlerts.Add(new SafetyAlert
                    {
                        UserId = child,
                        Username = child,
                        AlertType = "SCREEN_TIME_EXCEEDED",
                        Message = $"⏱️ [HẾT GIỜ SỬ DỤNG] Trẻ '{child}' đã dùng hết thời gian cho phép hôm nay ({totalUsed}/{effectiveLimit} phút){(!string.IsNullOrEmpty(exceededAppName) ? $" - Ứng dụng '{exceededAppName}' đã bị chặn!" : "!")}",
                        CreatedAt = DateTime.UtcNow,
                        IsResolved = false
                    });
                }
            }

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                childUsername = child,
                totalUsedMinutes = totalUsed,
                dailyLimitMinutes = effectiveLimit,
                remainingMinutes = Math.Max(0, effectiveLimit - totalUsed),
                isOverLimit = totalUsed >= effectiveLimit,
                approvedExtraMinutes = approvedExtra,
                appRules = rules
            });
        }

        /// <summary>
        /// Lấy thống kê chi tiết thời gian sử dụng thiết bị hôm nay của con
        /// </summary>
        [HttpGet("screen-time-stats")]
        public async Task<IActionResult> GetScreenTimeStats([FromQuery] string? childUsername)
        {
            var child = string.IsNullOrWhiteSpace(childUsername) ? "testuser01" : childUsername.Trim();
            var rules = await _context.AppRules.Where(r => r.ChildUsername == child).ToListAsync();
            if (rules.Count == 0)
            {
                rules = await _context.AppRules.Where(r => r.ChildUsername == "testuser01").ToListAsync();
            }

            int totalUsed = rules.Sum(r => r.UsedMinutesToday);
            int baseLimit = rules.Sum(r => r.DailyLimitMinutes);
            if (baseLimit <= 0) baseLimit = 120;

            var today = DateTime.UtcNow.Date;
            var approvedExtra = await _context.ChildRequests
                .Where(c => c.ChildUsername == child && c.Status == "APPROVED" && c.CreatedAt >= today)
                .SumAsync(c => c.ExtraMinutes);

            int effectiveLimit = baseLimit + approvedExtra;

            return Ok(new
            {
                status = true,
                childUsername = child,
                totalUsedMinutes = totalUsed,
                baseLimitMinutes = baseLimit,
                approvedExtraMinutes = approvedExtra,
                dailyLimitMinutes = effectiveLimit,
                remainingMinutes = Math.Max(0, effectiveLimit - totalUsed),
                isOverLimit = totalUsed >= effectiveLimit,
                appRules = rules
            });
        }

        // ==============================================================
        // 8. QUẢN LÝ LỊCH TRÌNH SINH HOẠT / HỌC TẬP (Schedules CRUD)
        // ==============================================================
        [HttpGet("schedules")]
        public async Task<IActionResult> GetSchedules([FromQuery] string? childUsername)
        {
            var query = _context.StudySchedules.AsNoTracking().AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
                query = query.Where(s => s.ChildUsername == childUsername);

            var schedules = await query.OrderBy(s => s.StartTime).ToListAsync();
            return Ok(schedules);
        }

        [HttpPost("schedules")]
        public async Task<IActionResult> CreateSchedule([FromBody] StudySchedule schedule)
        {
            if (string.IsNullOrWhiteSpace(schedule.Title))
                return BadRequest(new { status = false, message = "Tiêu đề lịch trình không được để trống" });

            schedule.CreatedAt = DateTime.UtcNow;
            _context.StudySchedules.Add(schedule);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new { status = true, message = $"Đã thêm lịch trình '{schedule.Title}' thành công!", data = schedule });
        }

        [HttpPut("schedules/{id}")]
        public async Task<IActionResult> UpdateSchedule(int id, [FromBody] StudySchedule update)
        {
            var schedule = await _context.StudySchedules.FindAsync(id);
            if (schedule == null) return NotFound(new { status = false, message = "Không tìm thấy lịch trình" });

            schedule.Title = string.IsNullOrWhiteSpace(update.Title) ? schedule.Title : update.Title;
            schedule.ScheduleType = string.IsNullOrWhiteSpace(update.ScheduleType) ? schedule.ScheduleType : update.ScheduleType;
            schedule.StartTime = string.IsNullOrWhiteSpace(update.StartTime) ? schedule.StartTime : update.StartTime;
            schedule.EndTime = string.IsNullOrWhiteSpace(update.EndTime) ? schedule.EndTime : update.EndTime;
            schedule.DaysOfWeek = string.IsNullOrWhiteSpace(update.DaysOfWeek) ? schedule.DaysOfWeek : update.DaysOfWeek;
            schedule.LockDeviceDuringSchedule = update.LockDeviceDuringSchedule;
            schedule.IsActive = update.IsActive;
            schedule.RequireLocationPresence = update.RequireLocationPresence;
            schedule.TargetLocationName = update.TargetLocationName ?? schedule.TargetLocationName;
            schedule.TargetAddress = update.TargetAddress ?? schedule.TargetAddress;
            schedule.TargetLatitude = update.TargetLatitude ?? schedule.TargetLatitude;
            schedule.TargetLongitude = update.TargetLongitude ?? schedule.TargetLongitude;
            schedule.TargetRadiusMeters = update.TargetRadiusMeters > 0 ? update.TargetRadiusMeters : schedule.TargetRadiusMeters;
            schedule.ChildUsername = string.IsNullOrWhiteSpace(update.ChildUsername) ? schedule.ChildUsername : update.ChildUsername;

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã cập nhật lịch trình thành công", data = schedule });
        }

        [HttpDelete("schedules/{id}")]
        public async Task<IActionResult> DeleteSchedule(int id)
        {
            var schedule = await _context.StudySchedules.FindAsync(id);
            if (schedule == null) return NotFound(new { status = false, message = "Không tìm thấy lịch trình" });

            _context.StudySchedules.Remove(schedule);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = $"Đã xóa lịch trình '{schedule.Title}'" });
        }

        [HttpPost("schedules/{id}/toggle-active")]
        public async Task<IActionResult> ToggleScheduleActive(int id)
        {
            var schedule = await _context.StudySchedules.FindAsync(id);
            if (schedule == null) return NotFound(new { status = false, message = "Không tìm thấy lịch trình" });

            schedule.IsActive = !schedule.IsActive;
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new
            {
                status = true,
                message = schedule.IsActive ? $"Đã kích hoạt lịch trình '{schedule.Title}'" : $"Đã tạm ngưng lịch trình '{schedule.Title}'",
                isActive = schedule.IsActive
            });
        }

        // ==============================================================
        // 9. VÙNG AN TOÀN & GEOFENCING (Safe Zones CRUD)
        // ==============================================================
        [HttpGet("safe-zones")]
        public async Task<IActionResult> GetSafeZones([FromQuery] string? childUsername)
        {
            var query = _context.SafeZones.AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
                query = query.Where(z => z.ChildUsername == childUsername);

            var zones = await query.ToListAsync();
            return Ok(zones);
        }

        [HttpPost("safe-zones")]
        public async Task<IActionResult> CreateSafeZone([FromBody] SafeZone zone)
        {
            if (string.IsNullOrWhiteSpace(zone.Name))
                return BadRequest(new { status = false, message = "Tên vùng an toàn không được để trống" });

            zone.CreatedAt = DateTime.UtcNow;
            _context.SafeZones.Add(zone);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new { status = true, message = $"Đã thiết lập vùng an toàn '{zone.Name}'!", data = zone });
        }

        [HttpPut("safe-zones/{id}")]
        public async Task<IActionResult> UpdateSafeZone(int id, [FromBody] SafeZone update)
        {
            var zone = await _context.SafeZones.FindAsync(id);
            if (zone == null) return NotFound(new { status = false, message = "Không tìm thấy vùng an toàn" });

            zone.Name = string.IsNullOrWhiteSpace(update.Name) ? zone.Name : update.Name;
            zone.Latitude = update.Latitude != 0 ? update.Latitude : zone.Latitude;
            zone.Longitude = update.Longitude != 0 ? update.Longitude : zone.Longitude;
            zone.RadiusMeters = update.RadiusMeters > 0 ? update.RadiusMeters : zone.RadiusMeters;
            zone.IsActive = update.IsActive;

            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = "Đã cập nhật vùng an toàn thành công", data = zone });
        }

        [HttpDelete("safe-zones/{id}")]
        public async Task<IActionResult> DeleteSafeZone(int id)
        {
            var zone = await _context.SafeZones.FindAsync(id);
            if (zone == null) return NotFound(new { status = false, message = "Không tìm thấy vùng an toàn" });

            _context.SafeZones.Remove(zone);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");
            return Ok(new { status = true, message = $"Đã xóa vùng an toàn '{zone.Name}'" });
        }

        public class GeofenceCheckModel
        {
            public string ChildUsername { get; set; } = string.Empty;
            public double Latitude { get; set; }
            public double Longitude { get; set; }
        }

        [HttpPost("check-geofence")]
        public async Task<IActionResult> CheckGeofence([FromBody] GeofenceCheckModel model)
        {
            var zones = await _context.SafeZones.Where(z => z.IsActive && (string.IsNullOrEmpty(model.ChildUsername) || z.ChildUsername == model.ChildUsername)).ToListAsync();
            if (!zones.Any())
                return Ok(new { status = true, isInside = true, message = "Chưa thiết lập vùng an toàn nào" });

            bool isInsideAny = false;
            string closestZone = string.Empty;
            double minDistance = double.MaxValue;

            foreach (var zone in zones)
            {
                // Haversine formula tính khoảng cách giữa 2 tọa độ (mét)
                double d = CalculateDistanceMeters(model.Latitude, model.Longitude, zone.Latitude, zone.Longitude);
                if (d < minDistance)
                {
                    minDistance = d;
                    closestZone = zone.Name;
                }
                if (d <= zone.RadiusMeters)
                {
                    isInsideAny = true;
                    break;
                }
            }

            if (!isInsideAny)
            {
                // Tự động tạo cảnh báo ra khỏi vùng an toàn
                var alert = new SafetyAlert
                {
                    UserId = model.ChildUsername,
                    Username = model.ChildUsername,
                    AlertType = "GEOFENCE_EXIT",
                    Message = $"CẢNH BÁO: Trẻ '{model.ChildUsername}' đã di chuyển ra ngoài vùng an toàn ({closestZone}, cách {Math.Round(minDistance)}m)!",
                    Latitude = model.Latitude,
                    Longitude = model.Longitude,
                    IsResolved = false,
                    CreatedAt = DateTime.UtcNow
                };
                _context.SafetyAlerts.Add(alert);
                await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

                return Ok(new
                {
                    status = true,
                    isInside = false,
                    message = $"Cảnh báo: Đã ra ngoài vùng an toàn! Cách {closestZone} khoảng {Math.Round(minDistance)}m",
                    alertCreated = true
                });
            }

            return Ok(new
            {
                status = true,
                isInside = true,
                message = $"Trẻ đang ở trong vùng an toàn an tâm ({closestZone})"
            });
        }

        private static double CalculateDistanceMeters(double lat1, double lon1, double lat2, double lon2)
        {
            var r = 6371e3; // bán kính Trái Đất theo mét
            var phi1 = lat1 * Math.PI / 180;
            var phi2 = lat2 * Math.PI / 180;
            var deltaPhi = (lat2 - lat1) * Math.PI / 180;
            var deltaLambda = (lon2 - lon1) * Math.PI / 180;

            var a = Math.Sin(deltaPhi / 2) * Math.Sin(deltaPhi / 2) +
                    Math.Cos(phi1) * Math.Cos(phi2) *
                    Math.Sin(deltaLambda / 2) * Math.Sin(deltaLambda / 2);
            var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));

            return r * c;
        }

        // ==============================================================
        // 9B. KIỂM TRA LỊCH TRÌNH CÓ MẶT BẮT BUỘC & CẢNH BÁO VẮNG MẶT
        // ==============================================================
        public class SchedulePresenceCheckRequest
        {
            public string ChildUsername { get; set; } = string.Empty;
            public double Latitude { get; set; }
            public double Longitude { get; set; }
            public string? AddressName { get; set; }
        }

        [HttpPost("check-schedule-presence")]
        public async Task<IActionResult> CheckSchedulePresenceEndpoint([FromBody] SchedulePresenceCheckRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.ChildUsername))
                return BadRequest(new { status = false, message = "ChildUsername is required" });

            var result = await CheckLocationSchedulePresenceAsync(req.ChildUsername, req.Latitude, req.Longitude, req.AddressName ?? "");
            return Ok(result);
        }

        private async Task<object> CheckLocationSchedulePresenceAsync(string username, double lat, double lng, string address)
        {
            try
            {
                var vnNow = DateTime.UtcNow.AddHours(7);
                var currentTime = vnNow.ToString("HH:mm");
                string todayVn = GetDayOfWeekVn(vnNow.DayOfWeek);

                var schedules = await _context.StudySchedules
                    .Where(s => s.IsActive && s.RequireLocationPresence && s.TargetLatitude.HasValue && s.TargetLongitude.HasValue &&
                               (string.IsNullOrEmpty(s.ChildUsername) || s.ChildUsername == username))
                    .ToListAsync();

                if (!schedules.Any())
                {
                    return new { hasSchedule = false, isCompliant = true, message = "Không có lịch trình yêu cầu địa điểm nào" };
                }

                foreach (var s in schedules)
                {
                    bool isDayMatch = string.IsNullOrEmpty(s.DaysOfWeek) || s.DaysOfWeek.Contains(todayVn);
                    bool isTimeMatch = IsCurrentTimeInSchedule(s.StartTime, s.EndTime, currentTime);

                    if (isDayMatch && isTimeMatch)
                    {
                        double dist = CalculateDistanceMeters(lat, lng, s.TargetLatitude!.Value, s.TargetLongitude!.Value);
                        if (dist > s.TargetRadiusMeters)
                        {
                            // Trẻ em không có mặt tại địa điểm!
                            // Kiểm tra xem đã có cảnh báo vắng mặt chưa giải quyết trong 15 phút gần nhất chưa để tránh lặp
                            var recentAlert = await _context.SafetyAlerts
                                .Where(a => a.Username == username && a.AlertType == "ABSENCE_ALERT" && !a.IsResolved && a.CreatedAt > DateTime.UtcNow.AddMinutes(-15))
                                .FirstOrDefaultAsync();

                            if (recentAlert == null)
                            {
                                var alert = new SafetyAlert
                                {
                                    UserId = username,
                                    Username = username,
                                    AlertType = "ABSENCE_ALERT",
                                    Message = $"🚨 [CẢNH BÁO VẮNG MẶT] Bé '{username}' KHÔNG CÓ MẶT tại '{s.TargetLocationName}' ({s.TargetAddress}) trong khung giờ {s.StartTime} - {s.EndTime}! Vị trí thực tế cách {Math.Round(dist)}m ({address}).",
                                    Latitude = lat,
                                    Longitude = lng,
                                    IsResolved = false,
                                    CreatedAt = DateTime.UtcNow
                                };
                                _context.SafetyAlerts.Add(alert);
                                await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

                                return new
                                {
                                    hasSchedule = true,
                                    isCompliant = false,
                                    scheduleTitle = s.Title,
                                    targetLocation = s.TargetLocationName,
                                    distance = Math.Round(dist),
                                    allowedRadius = s.TargetRadiusMeters,
                                    alertCreated = true,
                                    message = $"Cảnh báo: Con không có mặt tại {s.TargetLocationName}! Cách {Math.Round(dist)}m."
                                };
                            }

                            return new
                            {
                                hasSchedule = true,
                                isCompliant = false,
                                scheduleTitle = s.Title,
                                targetLocation = s.TargetLocationName,
                                distance = Math.Round(dist),
                                allowedRadius = s.TargetRadiusMeters,
                                alertCreated = false,
                                message = $"Cảnh báo: Con vẫn đang vắng mặt tại {s.TargetLocationName} (cách {Math.Round(dist)}m)."
                            };
                        }
                        else
                        {
                            return new
                            {
                                hasSchedule = true,
                                isCompliant = true,
                                scheduleTitle = s.Title,
                                targetLocation = s.TargetLocationName,
                                distance = Math.Round(dist),
                                message = $"An tâm: Con đang có mặt đúng giờ tại {s.TargetLocationName}!"
                            };
                        }
                    }
                }

                return new { hasSchedule = false, isCompliant = true, message = "Hiện tại ngoài khung giờ kiểm tra địa điểm" };
            }
            catch (Exception ex)
            {
                return new { error = ex.Message };
            }
        }

        private static bool IsCurrentTimeInSchedule(string startTime, string endTime, string currentTime)
        {
            if (TimeSpan.TryParse(startTime, out var start) &&
                TimeSpan.TryParse(endTime, out var end) &&
                TimeSpan.TryParse(currentTime, out var now))
            {
                if (start <= end)
                    return now >= start && now <= end;
                else
                    return now >= start || now <= end; // Vượt qua nửa đêm (e.g. 22:00 - 06:00)
            }
            return false;
        }

        private static string GetDayOfWeekVn(DayOfWeek dow)
        {
            return dow switch
            {
                DayOfWeek.Monday => "T2",
                DayOfWeek.Tuesday => "T3",
                DayOfWeek.Wednesday => "T4",
                DayOfWeek.Thursday => "T5",
                DayOfWeek.Friday => "T6",
                DayOfWeek.Saturday => "T7",
                DayOfWeek.Sunday => "CN",
                _ => "T2"
            };
        }

        // ==============================================================
        // 10. AI DIGITAL DETOX & MOOD COMPANION (Nhật ký cảm xúc & Hỗ trợ cai nghiện số)
        // ==============================================================
        [HttpGet("mood-entries")]
        public async Task<IActionResult> GetMoodEntries([FromQuery] string? childUsername)
        {
            var query = _context.MoodEntries.AsQueryable();
            if (!string.IsNullOrWhiteSpace(childUsername))
                query = query.Where(m => m.ChildUsername == childUsername);

            var list = await query.OrderByDescending(m => m.CreatedAt).Take(20).ToListAsync();
            return Ok(list);
        }

        [HttpPost("mood-entries")]
        public async Task<IActionResult> AddMoodEntry([FromBody] MoodEntry entry)
        {
            if (string.IsNullOrWhiteSpace(entry.ChildUsername))
                entry.ChildUsername = "testuser01";

            // AI Logic phân tích cảm xúc và thời gian sử dụng màn hình đưa ra lời khuyên khoa học
            string advice = GenerateAiDetoxAdvice(entry.Mood, entry.ScreenTimeMinutes);
            entry.AiAdvice = advice;
            entry.CreatedAt = DateTime.UtcNow;

            _context.MoodEntries.Add(entry);
            await _context.SaveChangesAsync();
            _cache.Remove("all_locations_cache");

            return Ok(new
            {
                status = true,
                message = "Đã lưu nhật ký tâm trạng và AI đã đưa ra phân tích cân bằng số!",
                entry = entry
            });
        }

        private static string GenerateAiDetoxAdvice(string mood, int screenMinutes)
        {
            string baseAdvice = "";
            if (screenMinutes > 180)
            {
                baseAdvice = "⚠️ Thời gian nhìn màn hình hôm nay rất cao (> 3 tiếng). Mắt và não bộ của bạn đang chịu áp lực lớn. Hãy dừng lại ngay 30 phút, nhìn ra xa vào cây xanh và chớp mắt liên tục.";
            }
            else if (screenMinutes > 120)
            {
                baseAdvice = "💡 Bạn đã dùng thiết bị hơn 2 tiếng. Nên áp dụng quy tắc 20-20-20: Mỗi 20 phút nhìn xa 20 feet (6m) trong 20 giây nhé!";
            }
            else
            {
                baseAdvice = "🌿 Thời gian sử dụng màn hình của bạn hôm nay rất điều độ và hợp lý!";
            }

            string moodAdvice = mood.ToLower() switch
            {
                "căng thẳng" or "stress" => " Tâm trạng bạn đang căng thẳng. Hãy hít thở sâu 4 giây - giữ 4 giây - thở ra 4 giây, uống 1 cốc nước ấm và vận động vươn vai.",
                "mệt mỏi" or "buồn ngủ" => " Bạn cảm thấy mệt mỏi. Ánh sáng xanh từ màn hình có thể làm suy giảm Melatonin. Bạn nên tắt máy trước giờ ngủ ít nhất 45 phút.",
                "buồn" => " Chia sẻ tâm sự cùng bố mẹ hoặc bạn bè thân thiết sẽ giúp tinh thần bạn nhẹ nhõm hơn nhiều thay vì lướt mạng xã hội.",
                "vui vẻ" or "hào hứng" => " Tinh thần bạn đang rất tích cực! Hãy tận dụng năng lượng này để hoàn thành bài tập sớm và tham gia thể thao ngoài trời cùng gia đình nhé!",
                _ => " Hãy duy trì lối sống cân bằng giữa học tập, vui chơi và giấc ngủ ngon."
            };

            return baseAdvice + moodAdvice;
        }
    }
}
