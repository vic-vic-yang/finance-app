class Category {
  final String id;
  final String name;
  final String type;
  final String? icon;
  final String? color;
  final bool isSystem;

  /// 父分类 id（null 表示一级分类）
  final String? parentId;
  /// 父分类名（仅当 parentId 非空时有值）
  final String? parentName;
  /// 父分类图标（仅当 parentId 非空时有值）
  final String? parentIcon;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.isSystem = false,
    this.parentId,
    this.parentName,
    this.parentIcon,
  });

  bool get isChild => parentId != null;
  bool get isRoot => parentId == null;

  /// 用于显示的全名："餐饮 › 早餐" / "餐饮"
  String get fullName =>
      parentName != null ? '$parentName › $name' : name;

  /// 用于显示的图标：子分类有自己图标用自己的，没有就用父的
  String get displayIcon => icon ?? parentIcon ?? '📂';

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        isSystem: json['isSystem'] as bool? ?? false,
        parentId: json['parentId'] as String?,
        parentName: json['parentName'] as String?,
        parentIcon: json['parentIcon'] as String?,
      );
}
