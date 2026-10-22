using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using System.Text;
using VuMinhDuc.Models;
using VuMinhDuc.Repository;
using VuMinhDuc.Services;

namespace VuMinhDuc
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var currentDir = Directory.GetCurrentDirectory();
            var contentRoot = File.Exists(Path.Combine(currentDir, "appsettings.json"))
                ? currentDir
                : Path.Combine(currentDir, "VuMinhDuc");

            var options = new WebApplicationOptions
            {
                Args = args,
                ContentRootPath = contentRoot
            };
            var builder = WebApplication.CreateBuilder(options);

            // 1. Cấu hình DbContext kết nối PostgreSQL (Supabase)
            var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
            builder.Services.AddDbContext<ApplicationDbContext>(options =>
            {
                options.UseNpgsql(connectionString);
                options.ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.RelationalEventId.PendingModelChangesWarning));
            });

            // 2. Cấu hình ASP.NET Core Identity
            builder.Services.AddIdentity<User, IdentityRole>(options =>
            {
                options.Password.RequireDigit = false;
                options.Password.RequireLowercase = false;
                options.Password.RequireNonAlphanumeric = false;
                options.Password.RequireUppercase = false;
                options.Password.RequiredLength = 6;
                options.User.RequireUniqueEmail = true;
            })
            .AddEntityFrameworkStores<ApplicationDbContext>()
            .AddDefaultTokenProviders();

            // 3. Cấu hình JWT Bearer Authentication
            var jwtSettings = builder.Configuration.GetSection("JWTKey");
            var secretKey = jwtSettings["Secret"] ?? "VuMinhDuc_Default_Secret_Key_At_Least_32_Characters_Long_123!";
            var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));

            builder.Services.AddAuthentication(options =>
            {
                options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
            })
            .AddJwtBearer(options =>
            {
                options.RequireHttpsMetadata = false;
                options.SaveToken = true;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    ValidIssuer = jwtSettings["ValidIssuer"] ?? "VuMinhDuc_API",
                    ValidAudience = jwtSettings["ValidAudience"] ?? "VuMinhDuc_MobileApp",
                    IssuerSigningKey = signingKey,
                    ClockSkew = TimeSpan.Zero
                };
            });

            // 4. Authorization & Repositories & Services DI
            builder.Services.AddMemoryCache();
            builder.Services.AddAuthorization();
            builder.Services.AddScoped<IProductRepository, ProductRepository>();
            builder.Services.AddSingleton<IOtpService, MemoryOtpService>();
            builder.Services.AddScoped<IEmailService, SmtpEmailService>();

            // 5. Cấu hình Controllers và Views
            builder.Services.AddControllersWithViews();

            // 6. Cấu hình Swagger kèm chức năng Bearer Token
            builder.Services.AddEndpointsApiExplorer();
            builder.Services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo
                {
                    Title = "VuMinhDuc API - Phân Quyền & OTP Auth",
                    Version = "v1",
                    Description = "Hệ thống xác thực Identity, OTP qua Email, Phân quyền Admin / Employee / Customer"
                });

                c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
                {
                    Description = "Nhập JWT token: Bearer {token}",
                    Name = "Authorization",
                    In = ParameterLocation.Header,
                    Type = SecuritySchemeType.ApiKey,
                    Scheme = "Bearer"
                });

                c.AddSecurityRequirement(new OpenApiSecurityRequirement
                {
                    {
                        new OpenApiSecurityScheme
                        {
                            Reference = new OpenApiReference
                            {
                                Type = ReferenceType.SecurityScheme,
                                Id = "Bearer"
                            }
                        },
                        Array.Empty<string>()
                    }
                });
            });

            // 7. CORS mở cho Flutter
            builder.Services.AddCors(options =>
            {
                options.AddPolicy("AllowAll", policy =>
                {
                    policy.AllowAnyOrigin()
                          .AllowAnyHeader()
                          .AllowAnyMethod();
                });
            });

            var app = builder.Build();

            // 8. Middleware & Routing (Tối ưu khởi động siêu tốc - Không cài data/seed thừa)
            app.UseSwagger();
            app.UseSwaggerUI(c =>
            {
                c.SwaggerEndpoint("/swagger/v1/swagger.json", "VuMinhDuc API v1");
            });

            if (!app.Environment.IsDevelopment())
            {
                app.UseExceptionHandler("/Home/Error");
                app.UseHsts();
            }

            app.UseDefaultFiles();
            app.UseStaticFiles();
            app.UseRouting();
            app.UseCors("AllowAll");

            app.UseAuthentication();
            app.UseAuthorization();

            app.MapControllers();
            app.MapFallbackToFile("index.html");

            app.Run();
        }
    }
}
