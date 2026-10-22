import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/app_models.dart';
import '../services/data_service.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final DataService _dataService = DataService();
  List<PostItem> _posts = [];
  bool _isLoading = true;
  String _currentUsername = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadPosts();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUsername = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      final posts = await _dataService.getPosts();
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _showCreatePostDialog({PostItem? existing}) {
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    final imageCtrl = TextEditingController(text: existing?.imageUrl ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(existing != null ? 'Chỉnh sửa bài viết' : 'Tạo bài viết mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Bạn đang nghĩ gì thế?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link hình ảnh (URL tùy chọn)',
                  prefixIcon: Icon(Icons.image_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final content = contentCtrl.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);

              if (existing != null && existing.id != null) {
                await _dataService.updatePost(
                  existing.id!,
                  PostItem(
                    id: existing.id,
                    author: existing.author,
                    avatarUrl: existing.avatarUrl,
                    content: content,
                    imageUrl: imageCtrl.text.trim().isNotEmpty ? imageCtrl.text.trim() : null,
                    createdAt: existing.createdAt,
                    likesCount: existing.likesCount,
                  ),
                );
              } else {
                await _dataService.createPost(
                  PostItem(
                    id: 0,
                    author: _currentUsername.isNotEmpty ? _currentUsername : 'User',
                    content: content,
                    imageUrl: imageCtrl.text.trim().isNotEmpty ? imageCtrl.text.trim() : null,
                    createdAt: DateTime.now(),
                  ),
                );
              }
              _loadPosts();
            },
            child: const Text('Đăng bài'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePostDialog(),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text('Đăng bài', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primary,
      ),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _posts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.feed_outlined, size: 64, color: AppTheme.textMuted),
                        const SizedBox(height: 12),
                        const Text('Chưa có bài viết nào', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _posts.length,
                    itemBuilder: (ctx, index) {
                      final post = _posts[index];
                      final isOwner = post.author == _currentUsername;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Author Header
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryLight,
                                backgroundImage: (post.avatarUrl != null && post.avatarUrl!.isNotEmpty)
                                    ? NetworkImage(post.avatarUrl!)
                                    : null,
                                child: (post.avatarUrl == null || post.avatarUrl!.isEmpty)
                                    ? Text(
                                        post.author.isNotEmpty ? post.author.substring(0, 1).toUpperCase() : 'U',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                      )
                                    : null,
                              ),
                              title: Text(post.author, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              subtitle: Text(
                                post.createdAt.toLocal().toString().substring(0, 16),
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              trailing: isOwner && post.id != null
                                  ? PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                                      onSelected: (val) async {
                                        if (val == 'edit') {
                                          _showCreatePostDialog(existing: post);
                                        } else if (val == 'delete') {
                                          await _dataService.deletePost(post.id!);
                                          _loadPosts();
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Sửa')])),
                                        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Colors.red))])),
                                      ],
                                    )
                                  : null,
                            ),

                            // Post Content
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                post.content,
                                style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.4),
                              ),
                            ),

                            // Optional Post Image
                            if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Image.network(
                                  post.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              ),

                            const Divider(height: 1, color: AppTheme.surfaceElevated),

                            // Actions Bar (Like / Comment)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 18, color: AppTheme.secondary),
                                    label: Text('${post.likesCount} Thích', style: const TextStyle(color: AppTheme.secondary)),
                                    onPressed: () async {
                                      if (post.id != null) {
                                        await _dataService.likePost(post.id!);
                                        _loadPosts();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.comment_outlined, size: 18, color: AppTheme.textSecondary),
                                    label: const Text('Bình luận', style: TextStyle(color: AppTheme.textSecondary)),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
