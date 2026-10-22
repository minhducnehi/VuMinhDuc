class Category {
  final int id;
  final String name;
  final String? description;
  final int productCount;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.productCount = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      productCount: json['productCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}

class ProductPost {
  final int? id;
  final String name;
  final double price;
  final String? image;
  final String? description;
  final int? categoryId;
  final Category? category;

  ProductPost({
    this.id,
    required this.name,
    required this.price,
    this.image,
    this.description,
    this.categoryId,
    this.category,
  });

  factory ProductPost.fromJson(Map<String, dynamic> json) {
    return ProductPost(
      id: json['id'],
      name: json['name'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      image: json['image'],
      description: json['description'],
      categoryId: json['categoryId'],
      category: json['category'] != null ? Category.fromJson(json['category']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'price': price,
      'image': image,
      'description': description,
      'categoryId': categoryId,
    };
  }
}

class PostItem {
  final int? id;
  final String author;
  final String? avatarUrl;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  int likesCount;

  PostItem({
    this.id,
    required this.author,
    this.avatarUrl,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.likesCount = 0,
  });

  factory PostItem.fromJson(Map<String, dynamic> json) {
    return PostItem(
      id: json['id'],
      author: json['author'] ?? 'Người dùng',
      avatarUrl: json['avatarUrl'],
      content: json['content'] ?? '',
      imageUrl: json['imageUrl'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      likesCount: json['likesCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'author': author,
      'avatarUrl': avatarUrl,
      'content': content,
      'imageUrl': imageUrl,
      'likesCount': likesCount,
    };
  }
}
