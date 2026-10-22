namespace VuMinhDuc.Services
{
    public interface IEmailService
    {
        Task SendOtpEmailAsync(string toEmail, string username, string otpCode);
    }
}
