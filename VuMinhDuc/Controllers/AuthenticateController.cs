using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using VuMinhDuc.Models;
using VuMinhDuc.Services;

namespace VuMinhDuc.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthenticateController : ControllerBase
    {
        private readonly UserManager<User> _userManager;
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly IConfiguration _configuration;
        private readonly IOtpService _otpService;
        private readonly IEmailService _emailService;

        public AuthenticateController(
            UserManager<User> userManager,
            RoleManager<IdentityRole> roleManager,
            IConfiguration configuration,
            IOtpService otpService,
            IEmailService emailService)
        {
            _userManager = userManager;
            _roleManager = roleManager;
            _configuration = configuration;
            _otpService = otpService;
            _emailService = emailService;
        }

        /// <summary>
        /// 1. Đăng ký tài khoản qua Email (Yêu cầu 1)
        /// Người dùng đăng ký mặc định là Customer. Chỉ Admin mới có quyền phân quyền.
        /// </summary>
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegistrationModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(new { status = false, message = "Dữ liệu không hợp lệ", errors = ModelState });

            var userExists = await _userManager.FindByNameAsync(model.Username);
            if (userExists != null)
                return BadRequest(new { status = false, message = "Tên đăng nhập đã tồn tại trong hệ thống" });

            var emailExists = await _userManager.FindByEmailAsync(model.Email);
            if (emailExists != null)
                return BadRequest(new { status = false, message = "Email này đã được sử dụng cho một tài khoản khác" });

            var user = new User
            {
                UserName = model.Username,
                Email = model.Email,
                PhoneNumber = model.PhoneNumber,
                Initials = model.Initials ?? (model.Username.Length > 2 ? model.Username.Substring(0, 2).ToUpper() : model.Username.ToUpper()),
                SecurityStamp = Guid.NewGuid().ToString()
            };

            var result = await _userManager.CreateAsync(user, model.Password);
            if (!result.Succeeded)
            {
                var errorMessages = string.Join("; ", result.Errors.Select(e => e.Description));
                return StatusCode(500, new { status = false, message = $"Đăng ký thất bại: {errorMessages}" });
            }

            // 2 vai trò được chọn khi đăng ký:
            // "Owner" (Chủ gia đình) hoặc "Member" (Thành viên trong gia đình)
            string assignedRole = "Member";
            if (!string.IsNullOrWhiteSpace(model.Role))
            {
                var roleTrim = model.Role.Trim();
                if (roleTrim.Equals("Owner", StringComparison.OrdinalIgnoreCase) || 
                    roleTrim.Equals("Chủ gia đình", StringComparison.OrdinalIgnoreCase))
                {
                    assignedRole = "Owner";
                }
                else
                {
                    assignedRole = "Member";
                }
            }

            // Đảm bảo tất cả các vai trò gia đình tồn tại trong hệ thống
            string[] requiredRoles = { "Owner", "Member", "Child", "Admin" };
            foreach (var r in requiredRoles)
            {
                if (!await _roleManager.RoleExistsAsync(r))
                {
                    await _roleManager.CreateAsync(new IdentityRole(r));
                }
            }

            await _userManager.AddToRoleAsync(user, assignedRole);

            return Ok(new
            {
                status = true,
                message = $"Đăng ký tài khoản '{user.UserName}' với vai trò '{(assignedRole == "Owner" ? "Chủ gia đình" : "Thành viên gia đình")}' thành công!",
                username = user.UserName,
                email = user.Email,
                role = assignedRole
            });
        }

        /// <summary>
        /// Danh sách người dùng dành riêng cho Admin để phân quyền
        /// </summary>
        [HttpGet("users")]
        public async Task<IActionResult> GetAllUsers()
        {
            var users = _userManager.Users.ToList();
            var userList = new List<object>();

            foreach (var u in users)
            {
                var userRoles = await _userManager.GetRolesAsync(u);
                userList.Add(new
                {
                    id = u.Id,
                    username = u.UserName,
                    email = u.Email,
                    phoneNumber = u.PhoneNumber,
                    role = userRoles.FirstOrDefault() ?? "Customer",
                    allRoles = userRoles
                });
            }

            return Ok(userList);
        }

        public class UpdateRoleRequest
        {
            public string Username { get; set; } = string.Empty;
            public string NewRole { get; set; } = "Customer";
        }

        /// <summary>
        /// Admin phân quyền cho người dùng (Admin, Employee, Customer)
        /// </summary>
        [HttpPost("assign-role")]
        public async Task<IActionResult> AssignRole([FromBody] UpdateRoleRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Username))
                return BadRequest(new { status = false, message = "Vui lòng chỉ định tài khoản cần phân quyền" });

            // 4 quyền hợp lệ: Admin, Owner, Member, Child
            string normalizedRole = request.NewRole;
            if (normalizedRole.Equals("Guardian", StringComparison.OrdinalIgnoreCase)) normalizedRole = "Member";
            if (normalizedRole.Equals("Customer", StringComparison.OrdinalIgnoreCase)) normalizedRole = "Member";
            if (normalizedRole.Equals("Employee", StringComparison.OrdinalIgnoreCase)) normalizedRole = "Member";

            var user = await _userManager.FindByNameAsync(request.Username);
            if (user == null)
                return NotFound(new { status = false, message = "Không tìm thấy người dùng" });

            if (!await _roleManager.RoleExistsAsync(normalizedRole))
            {
                await _roleManager.CreateAsync(new IdentityRole(normalizedRole));
            }

            var currentRoles = await _userManager.GetRolesAsync(user);
            await _userManager.RemoveFromRolesAsync(user, currentRoles);
            await _userManager.AddToRoleAsync(user, normalizedRole);

            return Ok(new
            {
                status = true,
                message = $"Đã cập nhật vai trò của tài khoản '{user.UserName}' thành '{normalizedRole}'",
                username = user.UserName,
                role = normalizedRole
            });
        }

        /// <summary>
        /// 2. Bước 1 Đăng nhập: Kiểm tra Tên đăng nhập + Mật khẩu -> Phát sinh mã OTP gửi về Email
        /// </summary>
        [HttpPost("login-request-otp")]
        public async Task<IActionResult> LoginRequestOtp([FromBody] PreLoginRequest model)
        {
            if (!ModelState.IsValid)
                return BadRequest(new { status = false, message = "Vui lòng nhập đầy đủ thông tin đăng nhập" });

            var user = await _userManager.FindByNameAsync(model.Username);
            if (user == null || !await _userManager.CheckPasswordAsync(user, model.Password))
            {
                return Unauthorized(new { status = false, message = "Tài khoản hoặc mật khẩu không chính xác!" });
            }

            // Sinh mã OTP 6 số
            var otp = _otpService.GenerateOtp(user.UserName!, user.Email ?? "user@domain.com");

            // Gửi OTP qua Gmail thật nếu có email hợp lệ
            string emailNotice = $"Đã gửi mã xác thực OTP 6 số đến email {user.Email}!";
            if (!string.IsNullOrWhiteSpace(user.Email) && user.Email.Contains("@"))
            {
                try
                {
                    await _emailService.SendOtpEmailAsync(user.Email, user.UserName ?? "Quý khách", otp);
                }
                catch (Exception ex)
                {
                    emailNotice = $"Đã tạo mã OTP cho tài khoản (Email {user.Email} không nhận được: {ex.Message})";
                }
            }

            return Ok(new
            {
                status = true,
                requireOtp = true,
                message = emailNotice,
                username = user.UserName,
                email = user.Email,
                demoOtp = otp
            });
        }

        /// <summary>
        /// 2. Bước 2 Đăng nhập: Xác minh mã OTP -> Cấp phát JWT Token & Role để phân quyền
        /// </summary>
        [HttpPost("login-verify-otp")]
        public async Task<IActionResult> LoginVerifyOtp([FromBody] VerifyOtpRequest model)
        {
            if (!ModelState.IsValid)
                return BadRequest(new { status = false, message = "Vui lòng nhập mã OTP" });

            var user = await _userManager.FindByNameAsync(model.Username);
            if (user == null)
                return BadRequest(new { status = false, message = "Người dùng không tồn tại" });

            var isOtpValid = _otpService.ValidateOtp(model.Username, model.OtpCode);
            if (!isOtpValid)
            {
                return BadRequest(new { status = false, message = "Mã OTP không chính xác hoặc đã hết hạn (5 phút)!" });
            }

            var userRoles = await _userManager.GetRolesAsync(user);
            var primaryRole = userRoles.FirstOrDefault() ?? "Customer";

            var authClaims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, user.UserName ?? string.Empty),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim(ClaimTypes.Email, user.Email ?? string.Empty),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim("role", primaryRole),
            };

            foreach (var role in userRoles)
            {
                authClaims.Add(new Claim(ClaimTypes.Role, role));
            }

            var token = GenerateJwtToken(authClaims);

            return Ok(new
            {
                status = true,
                message = "Đăng nhập và xác thực OTP thành công!",
                token = token,
                role = primaryRole,
                user = new
                {
                    username = user.UserName,
                    email = user.Email,
                    roles = userRoles
                }
            });
        }

        /// <summary>
        /// Đăng nhập trực tiếp (tương thích backward compatibility)
        /// </summary>
        [HttpPost("login")]
        public async Task<IActionResult> DirectLogin([FromBody] LoginModel model)
        {
            return await LoginRequestOtp(new PreLoginRequest
            {
                Username = model.Username,
                Password = model.Password
            });
        }

        private string GenerateJwtToken(IEnumerable<Claim> claims)
        {
            var jwtSettings = _configuration.GetSection("JWTKey");
            var secret = jwtSettings["Secret"] ?? throw new InvalidOperationException("JWT Secret is not configured");
            var authSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));

            var expiryHours = double.TryParse(jwtSettings["TokenExpiryTimeInHour"], out var h) ? h : 24;

            var tokenDescriptor = new SecurityTokenDescriptor
            {
                Subject = new ClaimsIdentity(claims),
                Expires = DateTime.UtcNow.AddHours(expiryHours),
                Issuer = jwtSettings["ValidIssuer"],
                Audience = jwtSettings["ValidAudience"],
                SigningCredentials = new SigningCredentials(authSigningKey, SecurityAlgorithms.HmacSha256)
            };

            var tokenHandler = new JwtSecurityTokenHandler();
            var token = tokenHandler.CreateToken(tokenDescriptor);
            return tokenHandler.WriteToken(token);
        }
    }
}
