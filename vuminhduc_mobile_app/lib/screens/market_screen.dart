import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/app_models.dart';
import '../services/data_service.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final DataService _dataService = DataService();
  final TextEditingController _searchController = TextEditingController();

  List<ProductPost> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final cats = await _dataService.getCategories();
      final prods = await _dataService.getProducts();
      setState(() {
        _categories = cats;
        _products = prods;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await _dataService.searchProducts(query);
      setState(() {
        _products = results;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  List<ProductPost> get _filteredProducts {
    if (_selectedCategoryId == null) return _products;
    return _products.where((p) => p.categoryId == _selectedCategoryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        children: [
          // Thanh tìm kiếm sản phẩm
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm sản phẩm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _handleSearch('');
                        },
                      )
                    : null,
              ),
              onSubmitted: _handleSearch,
              textInputAction: TextInputAction.search,
            ),
          ),

          // Lọc theo Danh mục (Category Chips)
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Tất cả'),
                      selected: _selectedCategoryId == null,
                      selectedColor: AppTheme.secondary,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedCategoryId = null);
                      },
                    ),
                  ),
                  ..._categories.map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${cat.name} (${cat.productCount})'),
                          selected: _selectedCategoryId == cat.id,
                          selectedColor: AppTheme.secondary,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryId = selected ? cat.id : null;
                            });
                          },
                        ),
                      )),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Grid Sản phẩm
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text(
                              'Không có sản phẩm nào',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (ctx, index) {
                          final item = _filteredProducts[index];
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Ảnh sản phẩm
                                Expanded(
                                  flex: 3,
                                  child: Container(
                                    color: AppTheme.surfaceElevated,
                                    child: (item.image != null && item.image!.startsWith('http'))
                                        ? Image.network(
                                            item.image!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 40, color: AppTheme.textMuted),
                                          )
                                        : const Icon(Icons.shopping_bag_outlined, size: 48, color: AppTheme.secondary),
                                  ),
                                ),
                                // Chi tiết tên & giá
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${item.price.toStringAsFixed(0)} ₫',
                                          style: const TextStyle(
                                            color: Colors.amberAccent,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
