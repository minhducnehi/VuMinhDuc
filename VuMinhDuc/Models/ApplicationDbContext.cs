using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace VuMinhDuc.Models
{
    public class ApplicationDbContext : IdentityDbContext<User>
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
            : base(options)
        {
        }

        public DbSet<Product> Products { get; set; }
        public DbSet<Category> Categories { get; set; }
        public DbSet<Post> Posts { get; set; }
        public DbSet<FamilyGroup> FamilyGroups { get; set; }
        public DbSet<MemberLocation> MemberLocations { get; set; }
        public DbSet<MemberLocationHistory> MemberLocationHistories { get; set; }
        public DbSet<SafetyAlert> SafetyAlerts { get; set; }
        public DbSet<ChildRequest> ChildRequests { get; set; }
        public DbSet<ChildDevice> ChildDevices { get; set; }
        public DbSet<AppRule> AppRules { get; set; }
        public DbSet<StudySchedule> StudySchedules { get; set; }
        public DbSet<SafeZone> SafeZones { get; set; }
        public DbSet<MoodEntry> MoodEntries { get; set; }

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);

            builder.Entity<User>().Property(u => u.Initials).HasMaxLength(20);

            // Cấu hình quan hệ Category - Product (1 - nhiều)
            builder.Entity<Product>()
                .HasOne(p => p.Category)
                .WithMany(c => c.Products)
                .HasForeignKey(p => p.CategoryId)
                .OnDelete(DeleteBehavior.SetNull);
        }
    }
}
