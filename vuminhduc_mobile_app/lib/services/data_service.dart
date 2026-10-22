import 'dart:convert';
import '../models/app_models.dart';
import 'api_client.dart';

class DataService {
  final ApiClient _api = ApiClient();

  // --- PRODUCTS ---
  Future<List<ProductPost>> getProducts() async {
    final res = await _api.get('ProductApi');
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((e) => ProductPost.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải sản phẩm: ${res.statusCode}');
  }

  Future<List<ProductPost>> searchProducts(String query) async {
    final res = await _api.get('ProductApi/search?query=${Uri.encodeComponent(query)}');
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((e) => ProductPost.fromJson(e)).toList();
    }
    return [];
  }

  Future<bool> createProduct(ProductPost product) async {
    final res = await _api.post('ProductApi', body: product.toJson());
    return res.statusCode == 200 || res.statusCode == 201;
  }

  Future<bool> updateProduct(int id, ProductPost product) async {
    final res = await _api.put('ProductApi/$id', body: product.toJson());
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<bool> deleteProduct(int id) async {
    final res = await _api.delete('ProductApi/$id');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  // --- CATEGORIES ---
  Future<List<Category>> getCategories() async {
    final res = await _api.get('Category');
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((e) => Category.fromJson(e)).toList();
    }
    return [];
  }

  Future<bool> createCategory(Category category) async {
    final res = await _api.post('Category', body: category.toJson());
    return res.statusCode == 200 || res.statusCode == 201;
  }

  Future<bool> updateCategory(int id, Category category) async {
    final res = await _api.put('Category/$id', body: category.toJson());
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<bool> deleteCategory(int id) async {
    final res = await _api.delete('Category/$id');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  // --- POSTS (FACEBOOK FEED) ---
  Future<List<PostItem>> getPosts() async {
    final res = await _api.get('PostApi');
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((e) => PostItem.fromJson(e)).toList();
    }
    return [];
  }

  Future<bool> createPost(PostItem post) async {
    final res = await _api.post('PostApi', body: post.toJson());
    return res.statusCode == 200 || res.statusCode == 201;
  }

  Future<bool> updatePost(int id, PostItem post) async {
    final res = await _api.put('PostApi/$id', body: post.toJson());
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<bool> deletePost(int id) async {
    final res = await _api.delete('PostApi/$id');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<void> likePost(int id) async {
    await _api.post('PostApi/$id/like');
  }
}
