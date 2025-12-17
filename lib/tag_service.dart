import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TagService {
  static const String _tagsKey = 'photo_tags';
  static const String _tagIndexKey = 'tag_index';

  /// Generate photo key from metadata: {width}_{height}_{createTime}
  static String generatePhotoKey(int width, int height, int createTime) {
    return '${width}_${height}_$createTime';
  }

  /// Get all tags for all photos: {"{width}_{height}_{createTime}":["tag1","tag2",...]}
  static Future<Map<String, List<String>>> getAllTags() async {
    final prefs = await SharedPreferences.getInstance();
    final tagsJson = prefs.getString(_tagsKey);
    if (tagsJson == null) {
      return {};
    }
    try {
      final Map<String, dynamic> decoded = json.decode(tagsJson);
      return decoded.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      );
    } catch (e) {
      return {};
    }
  }

  /// Get reverse index: {"tag1":["{width}_{height}_{createTime}",...]}
  static Future<Map<String, List<String>>> getTagIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final indexJson = prefs.getString(_tagIndexKey);
    if (indexJson == null) {
      return {};
    }
    try {
      final Map<String, dynamic> decoded = json.decode(indexJson);
      return decoded.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      );
    } catch (e) {
      return {};
    }
  }

  /// Get tags for a specific photo by key
  static Future<List<String>> getTags(String photoKey) async {
    final allTags = await getAllTags();
    return allTags[photoKey] ?? [];
  }

  /// Get photo keys that have all the specified tags
  static Future<Set<String>> getPhotosByTags(Set<String> tags) async {
    if (tags.isEmpty) {
      return {};
    }

    final tagIndex = await getTagIndex();
    debugPrint('TagService: getPhotosByTags - Looking for tags: $tags');
    debugPrint('TagService: Tag index has ${tagIndex.length} tags');

    if (tagIndex.isEmpty) {
      debugPrint('TagService: Tag index is empty, rebuilding...');
      await rebuildTagIndex();
      final rebuiltIndex = await getTagIndex();
      debugPrint(
        'TagService: After rebuild, tag index has ${rebuiltIndex.length} tags',
      );

      if (rebuiltIndex.isEmpty) {
        return {};
      }
      // Use rebuilt index
      final firstTagPhotos = Set<String>.from(rebuiltIndex[tags.first] ?? []);
      debugPrint(
        'TagService: Photos with "${tags.first}": ${firstTagPhotos.length}',
      );

      Set<String> result = firstTagPhotos;
      for (final tag in tags.skip(1)) {
        final photosWithTag = Set<String>.from(rebuiltIndex[tag] ?? []);
        debugPrint('TagService: Photos with "$tag": ${photosWithTag.length}');
        result = result.intersection(photosWithTag);
      }
      debugPrint('TagService: Final result: ${result.length} photos');
      return result;
    }

    // Start with photos that have the first tag
    final firstTagPhotos = tagIndex[tags.first] ?? [];
    debugPrint(
      'TagService: Photos with "${tags.first}": ${firstTagPhotos.length}',
    );
    Set<String> result = Set<String>.from(firstTagPhotos);

    // Intersect with photos that have each subsequent tag
    for (final tag in tags.skip(1)) {
      final photosWithTag = tagIndex[tag] ?? [];
      debugPrint('TagService: Photos with "$tag": ${photosWithTag.length}');
      result = result.intersection(Set<String>.from(photosWithTag));
    }

    debugPrint('TagService: Final result: ${result.length} photos');
    return result;
  }

  /// Add a tag to a photo
  static Future<void> addTag(String photoKey, String tag) async {
    final allTags = await getAllTags();
    final tags = allTags[photoKey] ?? [];

    if (!tags.contains(tag)) {
      tags.add(tag);
      allTags[photoKey] = tags;

      // Update reverse index
      final tagIndex = await getTagIndex();
      final photosWithTag = tagIndex[tag] ?? [];
      if (!photosWithTag.contains(photoKey)) {
        photosWithTag.add(photoKey);
        tagIndex[tag] = photosWithTag;
      }

      await _saveTags(allTags);
      await _saveTagIndex(tagIndex);

      // Debug: verify the update
      final verifyIndex = await getTagIndex();
      debugPrint('TagService: Added tag "$tag" to photo $photoKey');
      debugPrint(
        'TagService: Photos with tag "$tag": ${verifyIndex[tag]?.length ?? 0}',
      );
    }
  }

  /// Remove a tag from a photo
  static Future<void> removeTag(String photoKey, String tag) async {
    final allTags = await getAllTags();
    final tags = allTags[photoKey];

    if (tags != null && tags.contains(tag)) {
      tags.remove(tag);

      if (tags.isEmpty) {
        allTags.remove(photoKey);
      } else {
        allTags[photoKey] = tags;
      }

      // Update reverse index
      final tagIndex = await getTagIndex();
      final photosWithTag = tagIndex[tag];
      if (photosWithTag != null) {
        photosWithTag.remove(photoKey);
        if (photosWithTag.isEmpty) {
          tagIndex.remove(tag);
        } else {
          tagIndex[tag] = photosWithTag;
        }
      }

      await _saveTags(allTags);
      await _saveTagIndex(tagIndex);
    }
  }

  /// Delete all tags for a photo
  static Future<void> deleteAllTags(String photoKey) async {
    final allTags = await getAllTags();
    final tags = allTags[photoKey];

    if (tags != null) {
      // Update reverse index - remove this photo from all tags
      final tagIndex = await getTagIndex();
      for (final tag in tags) {
        final photosWithTag = tagIndex[tag];
        if (photosWithTag != null) {
          photosWithTag.remove(photoKey);
          if (photosWithTag.isEmpty) {
            tagIndex.remove(tag);
          } else {
            tagIndex[tag] = photosWithTag;
          }
        }
      }

      allTags.remove(photoKey);
      await _saveTags(allTags);
      await _saveTagIndex(tagIndex);
    }
  }

  /// Save tags to SharedPreferences
  static Future<void> _saveTags(Map<String, List<String>> tags) async {
    final prefs = await SharedPreferences.getInstance();
    final tagsJson = json.encode(tags);
    await prefs.setString(_tagsKey, tagsJson);
  }

  /// Save tag index to SharedPreferences
  static Future<void> _saveTagIndex(Map<String, List<String>> tagIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final indexJson = json.encode(tagIndex);
    await prefs.setString(_tagIndexKey, indexJson);
  }

  /// Get the tags data
  static Future<Map<String, List<String>>> getTagsData() async {
    return await getAllTags();
  }

  /// Get all unique tags across all photos
  static Future<Set<String>> getAllUniqueTags() async {
    final tagIndex = await getTagIndex();
    return tagIndex.keys.toSet();
  }

  /// Rebuild the reverse index from the main tags data (for migration/repair)
  static Future<void> rebuildTagIndex() async {
    final allTags = await getAllTags();
    final tagIndex = <String, List<String>>{};

    for (final entry in allTags.entries) {
      final photoKey = entry.key;
      final tags = entry.value;

      for (final tag in tags) {
        if (!tagIndex.containsKey(tag)) {
          tagIndex[tag] = [];
        }
        if (!tagIndex[tag]!.contains(photoKey)) {
          tagIndex[tag]!.add(photoKey);
        }
      }
    }

    await _saveTagIndex(tagIndex);
  }
}
