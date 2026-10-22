using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

namespace VuMinhDuc.Services
{
    public class SmtpEmailService : IEmailService
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<SmtpEmailService> _logger;

        public SmtpEmailService(IConfiguration configuration, ILogger<SmtpEmailService> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public async Task SendOtpEmailAsync(string toEmail, string username, string otpCode)
        {
            var host = _configuration["EmailSettings:Host"] ?? "smtp.gmail.com";
            var port = int.Parse(_configuration["EmailSettings:Port"] ?? "587");
            var senderEmail = _configuration["EmailSettings:SenderEmail"] ?? "";
            var senderPassword = _configuration["EmailSettings:SenderPassword"]?.Replace(" ", "").Trim() ?? "";
            var senderName = _configuration["EmailSettings:SenderName"] ?? "VuMinhDuc Auth Security";

            if (string.IsNullOrWhiteSpace(senderEmail) || string.IsNullOrWhiteSpace(senderPassword))
            {
                _logger.LogWarning("EmailSettings chưa được cấu hình đầy đủ. Bỏ qua việc gửi email.");
                return;
            }

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(senderName, senderEmail));
            message.To.Add(new MailboxAddress(username, toEmail));
            message.Subject = $"[{otpCode}] Mã xác thực OTP đăng nhập hệ thống - {senderName}";

            var bodyBuilder = new BodyBuilder
            {
                HtmlBody = $@"
<!DOCTYPE html>
<html>
<head>
  <meta charset='utf-8'>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f4f6f9; margin: 0; padding: 20px; }}
    .container {{ max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.08); border: 1px solid #e2e8f0; }}
    .header {{ background: linear-gradient(135deg, #4f46e5, #06b6d4); padding: 30px 20px; text-align: center; color: white; }}
    .header h1 {{ margin: 0; font-size: 22px; font-weight: 700; }}
    .content {{ padding: 30px 25px; color: #334155; line-height: 1.6; }}
    .otp-box {{ background: #f8fafc; border: 2px dashed #4f46e5; border-radius: 8px; padding: 18px; text-align: center; margin: 24px 0; }}
    .otp-code {{ font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #4f46e5; margin: 0; font-family: monospace; }}
    .notice {{ font-size: 13px; color: #64748b; margin-top: 15px; }}
    .footer {{ background: #f1f5f9; padding: 16px; text-align: center; font-size: 12px; color: #94a3b8; }}
  </style>
</head>
<body>
  <div class='container'>
    <div class='header'>
      <h1>XÁC THỰC ĐĂNG NHẬP (2FA)</h1>
    </div>
    <div class='content'>
      <p>Xin chào <strong>{username}</strong>,</p>
      <p>Hệ thống vừa nhận được yêu cầu đăng nhập vào tài khoản của bạn. Vui lòng sử dụng mã xác thực OTP dưới đây để hoàn tất quá trình đăng nhập:</p>
      
      <div class='otp-box'>
        <div class='otp-code'>{otpCode}</div>
      </div>

      <p class='notice'>
        ⏰ Mã xác thực này có hiệu lực trong vòng <strong>5 phút</strong>.<br>
        🛡️ Tuyệt đối không chia sẻ mã này cho bất kỳ ai để bảo vệ tài khoản của bạn.
      </p>
    </div>
    <div class='footer'>
      © {DateTime.UtcNow.Year} VuMinhDuc System. All rights reserved.
    </div>
  </div>
</body>
</html>"
            };

            message.Body = bodyBuilder.ToMessageBody();

            using var client = new SmtpClient();
            try
            {
                _logger.LogInformation("Đang kết nối SMTP {Host}:{Port} để gửi email OTP tới {Email}...", host, port, toEmail);
                
                await client.ConnectAsync(host, port, SecureSocketOptions.StartTls);
                await client.AuthenticateAsync(senderEmail, senderPassword);
                await client.SendAsync(message);
                await client.DisconnectAsync(true);

                _logger.LogInformation("Gửi email chứa mã OTP tới {Email} thành công!", toEmail);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi gửi email qua MailKit SMTP: {Message}", ex.Message);
                throw;
            }
        }
    }
}
