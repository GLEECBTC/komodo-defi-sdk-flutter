import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// NFT metadata extracted from token URI data.
class NftMetadata {
  const NftMetadata({
    this.image,
    this.imageUrl,
    this.imageDomain,
    this.name,
    this.description,
    this.attributes,
    this.animationUrl,
    this.animationDomain,
    this.externalUrl,
    this.externalDomain,
    this.imageDetails,
  });

  factory NftMetadata.fromJson(JsonMap json) {
    return NftMetadata(
      image: json.valueOrNull<String>('image'),
      imageUrl: json.valueOrNull<String>('image_url'),
      imageDomain: json.valueOrNull<String>('image_domain'),
      name: json.valueOrNull<String>('name'),
      description: json.valueOrNull<String>('description'),
      attributes: json.valueOrNull<dynamic>('attributes'),
      animationUrl: json.valueOrNull<String>('animation_url'),
      animationDomain: json.valueOrNull<String>('animation_domain'),
      externalUrl: json.valueOrNull<String>('external_url'),
      externalDomain: json.valueOrNull<String>('external_domain'),
      imageDetails: json.valueOrNull<JsonMap>('image_details'),
    );
  }

  /// Raw image value from metadata.
  final String? image;

  /// Resolved image URL, if KDF returned one.
  final String? imageUrl;

  /// Image URL domain.
  final String? imageDomain;

  /// NFT display name.
  final String? name;

  /// NFT description.
  final String? description;

  /// Raw metadata attributes payload.
  final dynamic attributes;

  /// Animation URL.
  final String? animationUrl;

  /// Animation URL domain.
  final String? animationDomain;

  /// External URL.
  final String? externalUrl;

  /// External URL domain.
  final String? externalDomain;

  /// Raw image detail payload.
  final JsonMap? imageDetails;

  Map<String, dynamic> toJson() => {
    if (image != null) 'image': image,
    if (imageUrl != null) 'image_url': imageUrl,
    if (imageDomain != null) 'image_domain': imageDomain,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (attributes != null) 'attributes': attributes,
    if (animationUrl != null) 'animation_url': animationUrl,
    if (animationDomain != null) 'animation_domain': animationDomain,
    if (externalUrl != null) 'external_url': externalUrl,
    if (externalDomain != null) 'external_domain': externalDomain,
    if (imageDetails != null) 'image_details': imageDetails,
  };
}
