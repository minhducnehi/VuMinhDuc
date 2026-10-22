using Microsoft.AspNetCore.Identity;

namespace VuMinhDuc.Models
{
    public class User : IdentityUser
    {
        public string? Initials { get; set; }
    }
}
