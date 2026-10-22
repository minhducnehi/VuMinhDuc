namespace VuMinhDuc.Models
{
    public class Post
    {
        public int Id { get; set; }
        public string Author { get; set; } = string.Empty;
        public string? AvatarUrl { get; set; }
        public string Content { get; set; } = string.Empty;
        public string? ImageUrl { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public int LikesCount { get; set; } = 0;
    }
}
