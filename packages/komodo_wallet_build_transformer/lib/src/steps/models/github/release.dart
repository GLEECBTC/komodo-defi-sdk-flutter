class Release {
  const Release({
    required this.url,
    required this.htmlUrl,
    required this.assetsUrl,
    required this.tagName,
    required this.targetCommitish,
    required this.author,
    required this.assets,
  });

  factory Release.fromJson(Map<String, dynamic> json) => Release(
    url: json['url'] as String,
    htmlUrl: json['html_url'] as String,
    assetsUrl: json['assets_url'] as String,
    tagName: json['tag_name'] as String,
    targetCommitish: json['target_commitish'] as String,
    author: SimpleUser.fromJson(json['author'] as Map<String, dynamic>),
    assets: (json['assets'] as List<dynamic>)
        .map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
  final String url;
  final String htmlUrl;
  final String assetsUrl;
  final String tagName;
  final String targetCommitish;
  final SimpleUser author;
  final List<ReleaseAsset> assets;

  Map<String, dynamic> toJson() => {
    'url': url,
    'html_url': htmlUrl,
    'assets_url': assetsUrl,
    'tag_name': tagName,
    'target_commitish': targetCommitish,
    'author': author.toJson(),
    'assets': assets.map((e) => e.toJson()).toList(),
  };

  Release copyWith({
    String? url,
    String? htmlUrl,
    String? assetsUrl,
    String? tagName,
    String? targetCommitish,
    SimpleUser? author,
    List<ReleaseAsset>? assets,
  }) {
    return Release(
      url: url ?? this.url,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      assetsUrl: assetsUrl ?? this.assetsUrl,
      tagName: tagName ?? this.tagName,
      targetCommitish: targetCommitish ?? this.targetCommitish,
      author: author ?? this.author,
      assets: assets ?? this.assets,
    );
  }
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.url,
    required this.browserDownloadUrl,
    required this.id,
    required this.nodeId,
    required this.name,
    required this.state,
    required this.contentType,
    required this.size,
    required this.downloadCount,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.uploader,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
    url: json['url'] as String,
    browserDownloadUrl: json['browser_download_url'] as String,
    id: (json['id'] as num).toInt(),
    nodeId: json['node_id'] as String,
    name: json['name'] as String,
    label: json['label'] as String?,
    state: json['state'] as String,
    contentType: json['content_type'] as String,
    size: (json['size'] as num).toInt(),
    downloadCount: (json['download_count'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    uploader: json['uploader'] != null
        ? SimpleUser.fromJson(json['uploader'] as Map<String, dynamic>)
        : null,
  );
  final String url;
  final String browserDownloadUrl;
  final int id;
  final String nodeId;
  final String name;
  final String? label;
  final String state;
  final String contentType;
  final int size;
  final int downloadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SimpleUser? uploader;

  Map<String, dynamic> toJson() => {
    'url': url,
    'browser_download_url': browserDownloadUrl,
    'id': id,
    'node_id': nodeId,
    'name': name,
    'label': label,
    'state': state,
    'content_type': contentType,
    'size': size,
    'download_count': downloadCount,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'uploader': uploader?.toJson(),
  };

  ReleaseAsset copyWith({
    String? url,
    String? browserDownloadUrl,
    int? id,
    String? nodeId,
    String? name,
    String? label,
    String? state,
    String? contentType,
    int? size,
    int? downloadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    SimpleUser? uploader,
  }) {
    return ReleaseAsset(
      url: url ?? this.url,
      browserDownloadUrl: browserDownloadUrl ?? this.browserDownloadUrl,
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      name: name ?? this.name,
      label: label ?? this.label,
      state: state ?? this.state,
      contentType: contentType ?? this.contentType,
      size: size ?? this.size,
      downloadCount: downloadCount ?? this.downloadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      uploader: uploader ?? this.uploader,
    );
  }
}

class SimpleUser {
  const SimpleUser({
    required this.login,
    required this.id,
    required this.nodeId,
    required this.avatarUrl,
    required this.url,
    required this.htmlUrl,
    required this.followersUrl,
    required this.followingUrl,
    required this.gistsUrl,
    required this.starredUrl,
    required this.subscriptionsUrl,
    required this.organizationsUrl,
    required this.reposUrl,
    required this.eventsUrl,
    required this.receivedEventsUrl,
    required this.type,
    required this.siteAdmin,
    this.name,
    this.email,
    this.gravatarId,
    this.starredAt,
  });

  factory SimpleUser.fromJson(Map<String, dynamic> json) => SimpleUser(
    name: json['name'] as String?,
    email: json['email'] as String?,
    login: json['login'] as String,
    id: (json['id'] as num).toInt(),
    nodeId: json['node_id'] as String,
    avatarUrl: json['avatar_url'] as String,
    gravatarId: json['gravatar_id'] as String?,
    url: json['url'] as String,
    htmlUrl: json['html_url'] as String,
    followersUrl: json['followers_url'] as String,
    followingUrl: json['following_url'] as String,
    gistsUrl: json['gists_url'] as String,
    starredUrl: json['starred_url'] as String,
    subscriptionsUrl: json['subscriptions_url'] as String,
    organizationsUrl: json['organizations_url'] as String,
    reposUrl: json['repos_url'] as String,
    eventsUrl: json['events_url'] as String,
    receivedEventsUrl: json['received_events_url'] as String,
    type: json['type'] as String,
    siteAdmin: json['site_admin'] as bool,
    starredAt: json['starred_at'] as String?,
  );

  final String? name;
  final String? email;
  final String login;
  final int id;
  final String nodeId;
  final String avatarUrl;
  final String? gravatarId;
  final String url;
  final String htmlUrl;
  final String followersUrl;
  final String followingUrl;
  final String gistsUrl;
  final String starredUrl;
  final String subscriptionsUrl;
  final String organizationsUrl;
  final String reposUrl;
  final String eventsUrl;
  final String receivedEventsUrl;
  final String type;
  final bool siteAdmin;
  final String? starredAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'login': login,
    'id': id,
    'node_id': nodeId,
    'avatar_url': avatarUrl,
    'gravatar_id': gravatarId,
    'url': url,
    'html_url': htmlUrl,
    'followers_url': followersUrl,
    'following_url': followingUrl,
    'gists_url': gistsUrl,
    'starred_url': starredUrl,
    'subscriptions_url': subscriptionsUrl,
    'organizations_url': organizationsUrl,
    'repos_url': reposUrl,
    'events_url': eventsUrl,
    'received_events_url': receivedEventsUrl,
    'type': type,
    'site_admin': siteAdmin,
    'starred_at': starredAt,
  };

  SimpleUser copyWith({
    String? name,
    String? email,
    String? login,
    int? id,
    String? nodeId,
    String? avatarUrl,
    String? gravatarId,
    String? url,
    String? htmlUrl,
    String? followersUrl,
    String? followingUrl,
    String? gistsUrl,
    String? starredUrl,
    String? subscriptionsUrl,
    String? organizationsUrl,
    String? reposUrl,
    String? eventsUrl,
    String? receivedEventsUrl,
    String? type,
    bool? siteAdmin,
    String? starredAt,
  }) {
    return SimpleUser(
      name: name ?? this.name,
      email: email ?? this.email,
      login: login ?? this.login,
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gravatarId: gravatarId ?? this.gravatarId,
      url: url ?? this.url,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      followersUrl: followersUrl ?? this.followersUrl,
      followingUrl: followingUrl ?? this.followingUrl,
      gistsUrl: gistsUrl ?? this.gistsUrl,
      starredUrl: starredUrl ?? this.starredUrl,
      subscriptionsUrl: subscriptionsUrl ?? this.subscriptionsUrl,
      organizationsUrl: organizationsUrl ?? this.organizationsUrl,
      reposUrl: reposUrl ?? this.reposUrl,
      eventsUrl: eventsUrl ?? this.eventsUrl,
      receivedEventsUrl: receivedEventsUrl ?? this.receivedEventsUrl,
      type: type ?? this.type,
      siteAdmin: siteAdmin ?? this.siteAdmin,
      starredAt: starredAt ?? this.starredAt,
    );
  }
}
