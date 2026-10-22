using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VuMinhDuc.Models;
using VuMinhDuc.Repository;

namespace VuMinhDuc.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ProductApiController : ControllerBase
    {
        private readonly IProductRepository _productRepository;

        public ProductApiController(IProductRepository productRepository)
        {
            _productRepository = productRepository;
        }

        // Lấy tất cả sản phẩm
        [HttpGet]
        public async Task<IActionResult> GetProducts()
        {
            try
            {
                var products = await _productRepository.GetProductsAsync();
                return Ok(products);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Lỗi khi tải danh sách sản phẩm", error = ex.Message });
            }
        }

        // Lấy chi tiết sản phẩm
        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetProductById(int id)
        {
            var product = await _productRepository.GetProductByIdAsync(id);
            if (product == null)
            {
                return NotFound(new { message = $"Không tìm thấy sản phẩm có id = {id}" });
            }
            return Ok(product);
        }

        // Tìm kiếm theo tên
        [HttpGet("search")]
        public async Task<IActionResult> Search([FromQuery] string query)
        {
            var results = await _productRepository.SearchByNameAsync(query ?? string.Empty);
            return Ok(results);
        }

        // Thêm sản phẩm (Yêu cầu quyền Admin)
        [HttpPost]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> AddProduct([FromBody] Product product)
        {
            if (!ModelState.IsValid)
            {
                return BadRequest(ModelState);
            }

            await _productRepository.AddProductAsync(product);
            return CreatedAtAction(nameof(GetProductById), new { id = product.Id }, product);
        }

        // Cập nhật sản phẩm (Yêu cầu quyền Admin)
        [HttpPut("{id:int}")]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> UpdateProduct(int id, [FromBody] Product product)
        {
            if (id != product.Id)
            {
                return BadRequest(new { message = "ID sản phẩm không khớp" });
            }

            await _productRepository.UpdateProductAsync(product);
            return Ok(new { message = "Cập nhật sản phẩm thành công", product });
        }

        // Xóa sản phẩm (Yêu cầu quyền Admin)
        [HttpDelete("{id:int}")]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> DeleteProduct(int id)
        {
            await _productRepository.DeleteProductAsync(id);
            return Ok(new { message = "Xóa sản phẩm thành công" });
        }
    }
}
