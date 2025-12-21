import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart' as yaml;

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

  /// Get photo keys that have any of the specified tags (OR logic)
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

      // Union all photos that have any of the selected tags (OR logic)
      Set<String> result = {};
      for (final tag in tags) {
        final photosWithTag = Set<String>.from(rebuiltIndex[tag] ?? []);
        debugPrint('TagService: Photos with "$tag": ${photosWithTag.length}');
        result = result.union(photosWithTag);
      }
      debugPrint(
        'TagService: Final result: ${result.length} photos (OR logic)',
      );
      return result;
    }

    // Union all photos that have any of the selected tags (OR logic)
    Set<String> result = {};
    for (final tag in tags) {
      final photosWithTag = tagIndex[tag] ?? [];
      debugPrint('TagService: Photos with "$tag": ${photosWithTag.length}');
      result = result.union(Set<String>.from(photosWithTag));
    }

    debugPrint('TagService: Final result: ${result.length} photos (OR logic)');
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

  /// Rename a tag across all photos
  static Future<void> renameTag(String oldTag, String newTag) async {
    if (oldTag == newTag || newTag.trim().isEmpty) {
      return;
    }

    final allTags = await getAllTags();
    final tagIndex = await getTagIndex();

    // Get all photos that have the old tag
    final photosWithOldTag = tagIndex[oldTag] ?? [];

    // Update each photo's tags
    for (final photoKey in photosWithOldTag) {
      final tags = allTags[photoKey];
      if (tags != null && tags.contains(oldTag)) {
        // Replace old tag with new tag
        final index = tags.indexOf(oldTag);
        tags[index] = newTag;
        allTags[photoKey] = tags;
      }
    }

    // Update tag index
    if (photosWithOldTag.isNotEmpty) {
      // Remove old tag from index
      tagIndex.remove(oldTag);

      // Add new tag to index with all photos
      final photosWithNewTag = tagIndex[newTag] ?? [];
      for (final photoKey in photosWithOldTag) {
        if (!photosWithNewTag.contains(photoKey)) {
          photosWithNewTag.add(photoKey);
        }
      }
      tagIndex[newTag] = photosWithNewTag;
    }

    await _saveTags(allTags);
    await _saveTagIndex(tagIndex);

    debugPrint(
      'TagService: Renamed tag "$oldTag" to "$newTag" across ${photosWithOldTag.length} photos',
    );
  }

  /// Delete a tag from all photos
  static Future<void> deleteTag(String tag) async {
    final allTags = await getAllTags();
    final tagIndex = await getTagIndex();

    // Get all photos that have this tag
    final photosWithTag = tagIndex[tag] ?? [];

    // Remove tag from each photo
    for (final photoKey in photosWithTag) {
      final tags = allTags[photoKey];
      if (tags != null && tags.contains(tag)) {
        tags.remove(tag);
        if (tags.isEmpty) {
          allTags.remove(photoKey);
        } else {
          allTags[photoKey] = tags;
        }
      }
    }

    // Remove tag from index
    tagIndex.remove(tag);

    await _saveTags(allTags);
    await _saveTagIndex(tagIndex);

    debugPrint(
      'TagService: Deleted tag "$tag" from ${photosWithTag.length} photos',
    );
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

  /// Export tags data to YAML string
  static Future<String> exportTagsToYamlString() async {
    final allTags = await getAllTags();
    final tagIndex = await getTagIndex();

    final exportData = <String, dynamic>{
      'photo_tags': allTags,
      'tag_index': tagIndex,
    };

    // Convert to YAML string
    return _mapToYaml(exportData);
  }

  /// Import tags data from YAML file
  static Future<void> importTagsFromYaml(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      final yamlString = await file.readAsString();
      final yamlDoc = yaml.loadYaml(yamlString);

      if (yamlDoc is! Map) {
        throw Exception('Invalid YAML format: expected a map');
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(yamlDoc);

      // Extract photo_tags and tag_index
      final photoTags = data['photo_tags'];
      final tagIndex = data['tag_index'];

      if (photoTags == null || tagIndex == null) {
        throw Exception('Invalid YAML format: missing photo_tags or tag_index');
      }

      // Convert to proper types
      final Map<String, List<String>> allTags = Map<String, List<String>>.from(
        Map<String, dynamic>.from(photoTags).map(
          (key, value) =>
              MapEntry(key.toString(), List<String>.from(value as List)),
        ),
      );

      final Map<String, List<String>> index = Map<String, List<String>>.from(
        Map<String, dynamic>.from(tagIndex).map(
          (key, value) =>
              MapEntry(key.toString(), List<String>.from(value as List)),
        ),
      );

      // Save imported data
      await _saveTags(allTags);
      await _saveTagIndex(index);

      debugPrint(
        'TagService: Imported ${allTags.length} photo tags and ${index.length} tag index entries',
      );
    } catch (e) {
      debugPrint('TagService: Error importing tags: $e');
      rethrow;
    }
  }

  /// Convert Map to YAML string
  static String _mapToYaml(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    buffer.writeln('# PhoTag Tags Export');
    buffer.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');

    // Write photo_tags
    final photoTags = map['photo_tags'] as Map<String, List<String>>;
    if (photoTags.isNotEmpty) {
      buffer.writeln('photo_tags:');
      for (final entry in photoTags.entries) {
        // Escape special characters in key
        final key = _escapeYamlString(entry.key);
        buffer.writeln('  "$key":');
        for (final tag in entry.value) {
          final escapedTag = _escapeYamlString(tag);
          buffer.writeln('    - "$escapedTag"');
        }
      }
    } else {
      buffer.writeln('photo_tags: {}');
    }

    buffer.writeln('');

    // Write tag_index
    final tagIndex = map['tag_index'] as Map<String, List<String>>;
    if (tagIndex.isNotEmpty) {
      buffer.writeln('tag_index:');
      for (final entry in tagIndex.entries) {
        // Escape special characters in key
        final key = _escapeYamlString(entry.key);
        buffer.writeln('  "$key":');
        for (final photoKey in entry.value) {
          final escapedKey = _escapeYamlString(photoKey);
          buffer.writeln('    - "$escapedKey"');
        }
      }
    } else {
      buffer.writeln('tag_index: {}');
    }

    return buffer.toString();
  }

  /// Escape special characters in YAML strings
  static String _escapeYamlString(String str) {
    return str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }
}
