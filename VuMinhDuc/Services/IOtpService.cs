using System.Collections.Concurrent;

namespace VuMinhDuc.Services
{
    public class OtpInfo
    {
        public string Code { get; set; } = string.Empty;
        public DateTime ExpiryTime { get; set; }
        public string Email { get; set; } = string.Empty;
    }

    public interface IOtpService
    {
        string GenerateOtp(string username, string email);
        bool ValidateOtp(string username, string code);
        string? GetLatestOtpForDemo(string username);
    }

    public class MemoryOtpService : IOtpService
    {
        private static readonly ConcurrentDictionary<string, OtpInfo> _otpStore = new(StringComparer.OrdinalIgnoreCase);

        public string GenerateOtp(string username, string email)
        {
            // Sinh mã OTP ngẫu nhiên 6 chữ số
            var random = new Random();
            var code = random.Next(100000, 999999).ToString();

            var otpInfo = new OtpInfo
            {
                Code = code,
                ExpiryTime = DateTime.UtcNow.AddMinutes(5), // Hết hạn sau 5 phút
                Email = email
            };

            _otpStore[username] = otpInfo;
            return code;
        }

        public bool ValidateOtp(string username, string code)
        {
            if (!_otpStore.TryGetValue(username, out var info))
            {
                return false;
            }

            if (DateTime.UtcNow > info.ExpiryTime)
            {
                _otpStore.TryRemove(username, out _);
                return false;
            }

            if (string.Equals(info.Code.Trim(), code.Trim(), StringComparison.Ordinal))
            {
                _otpStore.TryRemove(username, out _);
                return true;
            }

            return false;
        }

        public string? GetLatestOtpForDemo(string username)
        {
            if (_otpStore.TryGetValue(username, out var info) && DateTime.UtcNow <= info.ExpiryTime)
            {
                return info.Code;
            }
            return null;
        }
    }
}
