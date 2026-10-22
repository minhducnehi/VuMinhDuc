using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using VuMinhDuc.Models;

namespace VuMinhDuc.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class CategoryController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public CategoryController(ApplicationDbContext context)
        {
            _context = context;
        }

        // Lấy danh sách danh mục (Mọi người đều xem được)
        [HttpGet]
        public async Task<IActionResult> GetCategories()
        {
            try
            {
                var categories = await _context.Categories
                    .Select(c => new
                    {
                        c.Id,
                        c.Name,
                        c.Description,
                        ProductCount = c.Products != null ? c.Products.Count : 0
                    })
                    .ToListAsync();
                return Ok(categories);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi lấy danh mục: " + ex.Message });
            }
        }

        // Lấy chi tiết danh mục kèm sản phẩm
        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetCategoryById(int id)
        {
            try
            {
                var category = await _context.Categories
                    .Include(c => c.Products)
                    .FirstOrDefaultAsync(c => c.Id == id);

                if (category == null) return NotFound(new { message = "Không tìm thấy danh mục" });
                return Ok(category);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi: " + ex.Message });
            }
        }

        // Admin có quyền Thêm danh mục
        [HttpPost]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> CreateCategory([FromBody] Category category)
        {
            try
            {
                if (!ModelState.IsValid) return BadRequest(ModelState);
                _context.Categories.Add(category);
                await _context.SaveChangesAsync();
                return CreatedAtAction(nameof(GetCategoryById), new { id = category.Id }, category);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi thêm danh mục: " + ex.Message });
            }
        }

        // Admin có quyền Sửa danh mục
        [HttpPut("{id:int}")]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> UpdateCategory(int id, [FromBody] Category category)
        {
            try
            {
                if (id != category.Id) return BadRequest(new { message = "ID không khớp" });
                _context.Entry(category).State = EntityState.Modified;
                await _context.SaveChangesAsync();
                return Ok(new { status = true, message = "Cập nhật danh mục thành công!" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi cập nhật: " + ex.Message });
            }
        }

        // Admin có quyền Xóa danh mục
        // Xóa danh mục thì các sản phẩm không bị xóa mà về null
        [HttpDelete("{id:int}")]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> DeleteCategory(int id)
        {
            try
            {
                var category = await _context.Categories
                    .Include(c => c.Products)
                    .FirstOrDefaultAsync(c => c.Id == id);

                if (category == null) return NotFound(new { message = "Không tìm thấy danh mục để xóa" });

                if (category.Products != null && category.Products.Any())
                {
                    foreach (var p in category.Products)
                    {
                        p.CategoryId = null;
                    }
                }

                _context.Categories.Remove(category);
                await _context.SaveChangesAsync();
                return Ok(new { status = true, message = "Xóa danh mục thành công, các sản phẩm liên quan đã được gán về chưa phân loại" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi xóa danh mục: " + ex.Message });
            }
        }
    }
}
