using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using VuMinhDuc.Models;

namespace VuMinhDuc.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PostApiController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public PostApiController(ApplicationDbContext context)
        {
            _context = context;
        }

        // 1. Lấy danh sách bài đăng (Feed)
        [HttpGet]
        public async Task<IActionResult> GetPosts()
        {
            try
            {
                var posts = await _context.Posts
                    .OrderByDescending(p => p.CreatedAt)
                    .ToListAsync();
                return Ok(posts);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi khi tải bảng tin", error = ex.Message });
            }
        }

        // 2. Lấy chi tiết bài đăng
        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetPostById(int id)
        {
            var post = await _context.Posts.FindAsync(id);
            if (post == null) return NotFound(new { message = "Không tìm thấy bài đăng" });
            return Ok(post);
        }

        // 3. Đăng bài mới (Yêu cầu đăng nhập)
        [HttpPost]
        [Authorize]
        public async Task<IActionResult> CreatePost([FromBody] Post post)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            if (string.IsNullOrWhiteSpace(post.Author))
            {
                post.Author = User.Identity?.Name ?? "Ẩn danh";
            }
            post.CreatedAt = DateTime.UtcNow;

            _context.Posts.Add(post);
            await _context.SaveChangesAsync();
            return CreatedAtAction(nameof(GetPostById), new { id = post.Id }, post);
        }

        // 4. Cập nhật bài đăng (Tác giả hoặc Admin)
        [HttpPut("{id:int}")]
        [Authorize]
        public async Task<IActionResult> UpdatePost(int id, [FromBody] Post post)
        {
            if (id != post.Id) return BadRequest(new { message = "ID không trùng khớp" });

            var existing = await _context.Posts.FindAsync(id);
            if (existing == null) return NotFound(new { message = "Không tìm thấy bài đăng" });

            // Kiểm tra quyền: tác giả hoặc Admin
            var currentUsername = User.Identity?.Name;
            var isAdmin = User.IsInRole("Admin");
            if (existing.Author != currentUsername && !isAdmin)
            {
                return Forbid();
            }

            existing.Content = post.Content;
            existing.ImageUrl = post.ImageUrl;
            await _context.SaveChangesAsync();
            return Ok(new { status = true, message = "Cập nhật bài đăng thành công!", post = existing });
        }

        // 5. Thích bài đăng (Like)
        [HttpPost("{id:int}/like")]
        public async Task<IActionResult> LikePost(int id)
        {
            var post = await _context.Posts.FindAsync(id);
            if (post == null) return NotFound(new { message = "Không tìm thấy bài đăng" });

            post.LikesCount += 1;
            await _context.SaveChangesAsync();
            return Ok(new { status = true, likesCount = post.LikesCount });
        }

        // 6. Xóa bài đăng (Tác giả hoặc Admin)
        [HttpDelete("{id:int}")]
        [Authorize]
        public async Task<IActionResult> DeletePost(int id)
        {
            var post = await _context.Posts.FindAsync(id);
            if (post == null) return NotFound(new { message = "Không tìm thấy bài đăng" });

            var currentUsername = User.Identity?.Name;
            var isAdmin = User.IsInRole("Admin");
            if (existingAuthorCheck(post.Author, currentUsername) && !isAdmin)
            {
                return Forbid();
            }

            _context.Posts.Remove(post);
            await _context.SaveChangesAsync();
            return Ok(new { status = true, message = "Đã xóa bài đăng thành công" });
        }

        private bool existingAuthorCheck(string author, string? currentUsername)
        {
            return !string.Equals(author, currentUsername, StringComparison.OrdinalIgnoreCase);
        }
    }
}
