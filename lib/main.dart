import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';
import 'dart:typed_data';
import 'tag_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phoorg - Photo Gallery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PhotoGalleryScreen(),
    );
  }
}

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key});

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  List<AssetEntity> _photos = [];
  List<AssetEntity> _filteredPhotos = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String _errorMessage = '';
  bool _isSelectionMode = false;

  // Use ValueNotifier for efficient selection updates
  final ValueNotifier<Set<String>> _selectedPhotoIdsNotifier =
      ValueNotifier<Set<String>>({});

  // Tag filtering
  Set<String> _allTags = {};
  Set<String> _selectedFilterTags = {};
  Map<String, String> _photoKeyCache =
      {}; // Cache photo keys (width_height_createTime)

  @override
  void initState() {
    super.initState();
    _initializeTags();
    _requestPermissionAndLoadPhotos();
  }

  Future<void> _initializeTags() async {
    // Always rebuild tag index to ensure it's in sync
    final allTags = await TagService.getAllTags();
    final tagIndex = await TagService.getTagIndex();

    // If we have tags but index is empty or inconsistent, rebuild it
    if (allTags.isNotEmpty &&
        (tagIndex.isEmpty || _needsRebuild(allTags, tagIndex))) {
      debugPrint('Rebuilding tag index...');
      await TagService.rebuildTagIndex();
    }
    await _loadAllTags();
  }

  bool _needsRebuild(
    Map<String, List<String>> allTags,
    Map<String, List<String>> tagIndex,
  ) {
    // Check if all tags in allTags exist in tagIndex
    final Set<String> tagsInData = {};
    for (final tags in allTags.values) {
      tagsInData.addAll(tags);
    }
    return tagsInData.difference(tagIndex.keys.toSet()).isNotEmpty;
  }

  @override
  void dispose() {
    _selectedPhotoIdsNotifier.dispose();
    super.dispose();
  }

  Set<String> get _selectedPhotoIds => _selectedPhotoIdsNotifier.value;

  Future<void> _loadAllTags() async {
    final tags = await TagService.getAllUniqueTags();
    debugPrint('Loaded ${tags.length} unique tags: $tags');
    setState(() {
      _allTags = tags;
    });
  }

  Future<void> _applyFilters() async {
    if (_selectedFilterTags.isEmpty) {
      setState(() {
        _filteredPhotos = _photos;
      });
      return;
    }

    // Use reverse index to get photo keys that have all selected tags
    final matchingPhotoKeys = await TagService.getPhotosByTags(
      _selectedFilterTags,
    );

    debugPrint('Filtering: Selected tags: $_selectedFilterTags');
    debugPrint(
      'Filtering: Matching photo keys count: ${matchingPhotoKeys.length}',
    );
    debugPrint('Filtering: Matching photo keys: $matchingPhotoKeys');

    if (matchingPhotoKeys.isEmpty) {
      debugPrint('Filtering: No matching photo keys, clearing filtered photos');
      setState(() {
        _filteredPhotos = [];
      });
      return;
    }

    // Build photo key map for all photos (get metadata - fast!)
    debugPrint(
      'Filtering: Building photo key map for ${_photos.length} photos...',
    );
    final Map<String, AssetEntity> keyToPhotoMap = {};
    int cachedCount = 0;
    int calculatedCount = 0;

    for (final photo in _photos) {
      final photoKey = await _getPhotoKey(photo);
      if (photoKey != null) {
        keyToPhotoMap[photoKey] = photo;
        if (_photoKeyCache.containsKey(photo.id)) {
          cachedCount++;
        } else {
          calculatedCount++;
        }
      }
    }

    debugPrint('Filtering: Photo key map size: ${keyToPhotoMap.length}');
    debugPrint('Filtering: Cached: $cachedCount, Calculated: $calculatedCount');
    debugPrint(
      'Filtering: Photo key map keys sample: ${keyToPhotoMap.keys.take(3).toList()}',
    );

    // Filter photos by matching photo keys
    final filtered = <AssetEntity>[];
    int matchedCount = 0;
    for (final photoKey in matchingPhotoKeys) {
      final photo = keyToPhotoMap[photoKey];
      if (photo != null) {
        filtered.add(photo);
        matchedCount++;
        debugPrint('Filtering: ✓ Matched photo key $photoKey');
      } else {
        debugPrint('Filtering: ✗ Photo key $photoKey not found in photo map!');
        debugPrint(
          'Filtering: Available photo keys: ${keyToPhotoMap.keys.take(5).toList()}',
        );
      }
    }

    debugPrint(
      'Filtering: Matched $matchedCount out of ${matchingPhotoKeys.length} photo keys',
    );
    debugPrint('Filtering: Filtered photos count: ${filtered.length}');

    setState(() {
      _filteredPhotos = filtered;
      debugPrint('Filtering: setState called with ${filtered.length} photos');
    });
  }

  Future<String?> _getPhotoKey(AssetEntity photo) async {
    // Check cache first
    if (_photoKeyCache.containsKey(photo.id)) {
      return _photoKeyCache[photo.id];
    }

    try {
      // Get photo metadata - this is fast, no file reading needed!
      final width = photo.width;
      final height = photo.height;
      final createTime = photo.createDateTime.millisecondsSinceEpoch;

      final photoKey = TagService.generatePhotoKey(width, height, createTime);
      _photoKeyCache[photo.id] = photoKey;
      return photoKey;
    } catch (e) {
      debugPrint('Error getting photo key for photo ${photo.id}: $e');
    }
    return null;
  }

  void _toggleFilterTag(String tag) {
    setState(() {
      if (_selectedFilterTags.contains(tag)) {
        _selectedFilterTags.remove(tag);
      } else {
        _selectedFilterTags.add(tag);
      }
    });
    _applyFilters();
  }

  void _clearFilters() {
    setState(() {
      _selectedFilterTags.clear();
    });
    _applyFilters();
  }

  Future<void> _requestPermissionAndLoadPhotos() async {
    try {
      // Request permission
      final PermissionState ps = await PhotoManager.requestPermissionExtend();

      if (ps.isAuth) {
        setState(() {
          _hasPermission = true;
        });
        await _loadPhotos();
      } else {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
          _errorMessage =
              'Permission denied. Please grant photo access permission in settings.';
        });
        PhotoManager.openSetting();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error requesting permission: $e';
      });
    }
  }

  Future<void> _loadPhotos() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get all photo albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );

      if (albums.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No photos found on device.';
        });
        return;
      }

      // Get all photos from the "Recent" or first album
      final AssetPathEntity recentAlbum = albums.first;
      final List<AssetEntity> photos = await recentAlbum.getAssetListRange(
        start: 0,
        end: 10000, // Load up to 10000 photos
      );

      setState(() {
        _photos = photos;
        _filteredPhotos = photos; // Initialize filtered photos with all photos
        _isLoading = false;
        // Clear selection when reloading
        _selectedPhotoIdsNotifier.value = {};
        _isSelectionMode = false;
        // Clear photo key cache
        _photoKeyCache.clear();
      });

      // Load tags and apply filters
      await _loadAllTags();
      await _applyFilters();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading photos: $e';
      });
    }
  }

  Future<void> _refreshPhotos() async {
    await _loadPhotos();
    await _loadAllTags();
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedPhotoIdsNotifier.value = {};
      }
    });
  }

  void _togglePhotoSelection(String photoId) {
    final newSet = Set<String>.from(_selectedPhotoIds);
    if (newSet.contains(photoId)) {
      newSet.remove(photoId);
    } else {
      newSet.add(photoId);
    }
    _selectedPhotoIdsNotifier.value = newSet;

    // Exit selection mode if no photos selected
    if (newSet.isEmpty && _isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotoIds.isEmpty) return;

    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photos'),
        content: Text(
          'Are you sure you want to delete ${_selectedPhotoIds.length} photo(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Get the selected assets
      final List<AssetEntity> selectedAssets = _photos
          .where((photo) => _selectedPhotoIds.contains(photo.id))
          .toList();

      // Delete the photos
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(
        selectedAssets.map((e) => e.id).toList(),
      );

      // Remove deleted photos from the list
      setState(() {
        _photos.removeWhere((photo) => deletedIds.contains(photo.id));
        _selectedPhotoIdsNotifier.value = {};
        _isSelectionMode = false;
        // Clear photo key cache for deleted photos
        for (final id in deletedIds) {
          _photoKeyCache.remove(id);
        }
      });

      // Refresh filters and tags
      await _applyFilters();
      await _loadAllTags();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${deletedIds.length} photo(s) deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: ValueListenableBuilder<Set<String>>(
          valueListenable: _selectedPhotoIdsNotifier,
          builder: (context, selectedIds, _) {
            return Text(
              _isSelectionMode
                  ? '${selectedIds.length} selected'
                  : 'Photo Gallery',
            );
          },
        ),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
                tooltip: 'Cancel selection',
              )
            : null,
        actions: [
          if (_isSelectionMode)
            ValueListenableBuilder<Set<String>>(
              valueListenable: _selectedPhotoIdsNotifier,
              builder: (context, selectedIds, _) {
                return IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: selectedIds.isEmpty ? null : _deleteSelectedPhotos,
                  tooltip: 'Delete selected',
                );
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _hasPermission && _photos.isNotEmpty
                  ? _toggleSelectionMode
                  : null,
              tooltip: 'Select photos',
            ),
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _hasPermission ? _refreshPhotos : null,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading photos...'),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'Photo Access Permission Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _requestPermissionAndLoadPhotos,
                icon: const Icon(Icons.settings),
                label: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty && _photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshPhotos,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_photos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No photos found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tag filter section
        if (_allTags.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Filter by tags:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedFilterTags.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allTags.map((tag) {
                    final isSelected = _selectedFilterTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (selected) => _toggleFilterTag(tag),
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      checkmarkColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                if (_selectedFilterTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Showing ${_filteredPhotos.length} of ${_photos.length} photos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _filteredPhotos.isEmpty && _selectedFilterTags.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.filter_alt_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No photos match the selected tags',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                )
              : Builder(
                  builder: (context) {
                    final useFiltered = _selectedFilterTags.isNotEmpty;
                    final photosToShow = useFiltered
                        ? _filteredPhotos
                        : _photos;
                    debugPrint(
                      'GridView: useFiltered=$useFiltered, showing ${photosToShow.length} photos',
                    );
                    return GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: photosToShow.length,
                      itemBuilder: (context, index) {
                        final asset = photosToShow[index];
                        return RepaintBoundary(
                          key: ValueKey(asset.id),
                          child: _PhotoThumbnail(
                            asset: asset,
                            isSelectionMode: _isSelectionMode,
                            selectedPhotoIdsNotifier: _selectedPhotoIdsNotifier,
                            onTap: _isSelectionMode
                                ? () => _togglePhotoSelection(asset.id)
                                : null,
                            onLongPress: !_isSelectionMode
                                ? () {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedPhotoIdsNotifier.value = {
                                        asset.id,
                                      };
                                    });
                                  }
                                : null,
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: _selectedPhotoIdsNotifier,
          builder: (context, selectedIds, _) {
            if (_isSelectionMode && selectedIds.isNotEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${selectedIds.length} photo(s) selected',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ElevatedButton.icon(
                        onPressed: _deleteSelectedPhotos,
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

class _PhotoThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final ValueNotifier<Set<String>> selectedPhotoIdsNotifier;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PhotoThumbnail({
    required this.asset,
    required this.isSelectionMode,
    required this.selectedPhotoIdsNotifier,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<_PhotoThumbnail> {
  Uint8List? _thumbnailData;
  bool _isLoadingThumbnail = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final thumbnail = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
      );
      if (mounted && thumbnail != null) {
        setState(() {
          _thumbnailData = thumbnail;
          _isLoadingThumbnail = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
        });
      }
      debugPrint('Error loading thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap ?? () => _showFullImage(context),
      onLongPress: widget.onLongPress,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _isLoadingThumbnail
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _thumbnailData != null
                  ? Image.memory(
                      _thumbnailData!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          if (widget.isSelectionMode)
            ValueListenableBuilder<Set<String>>(
              valueListenable: widget.selectedPhotoIdsNotifier,
              builder: (context, selectedIds, _) {
                final isSelected = selectedIds.contains(widget.asset.id);
                return Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue
                          : Colors.white.withOpacity(0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : const SizedBox(width: 16, height: 16),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullImageScreen(asset: widget.asset),
      ),
    );
    // Refresh gallery if photo was deleted or tags were updated
    final state = context.findAncestorStateOfType<_PhotoGalleryScreenState>();
    if (result == true) {
      await state?._refreshPhotos();
    } else {
      // Refresh tags and filters even if photo wasn't deleted
      await state?._loadAllTags();
      await state?._applyFilters();
    }
  }
}

class _FullImageScreen extends StatefulWidget {
  final AssetEntity asset;

  const _FullImageScreen({required this.asset});

  @override
  State<_FullImageScreen> createState() => _FullImageScreenState();
}

class _FullImageScreenState extends State<_FullImageScreen> {
  List<String> _tags = [];
  String? _photoKey;
  bool _isLoadingKey = false;
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      setState(() {
        _isLoadingKey = true;
      });

      // Get photo metadata - fast, no file reading needed!
      final width = widget.asset.width;
      final height = widget.asset.height;
      final createTime = widget.asset.createDateTime.millisecondsSinceEpoch;
      final photoKey = TagService.generatePhotoKey(width, height, createTime);

      setState(() {
        _photoKey = photoKey;
        _isLoadingKey = false;
      });

      final tags = await TagService.getTags(photoKey);
      setState(() {
        _tags = tags;
      });
    } catch (e) {
      setState(() {
        _isLoadingKey = false;
      });
      debugPrint('Error loading tags: $e');
    }
  }

  Future<void> _addTag(String tag) async {
    if (tag.trim().isEmpty || _photoKey == null) return;
    final trimmedTag = tag.trim();
    if (_tags.contains(trimmedTag)) return;

    await TagService.addTag(_photoKey!, trimmedTag);
    setState(() {
      _tags = List.from(_tags)..add(trimmedTag);
    });
    _tagController.clear();

    // Notify parent to refresh tags and filters
    final state = context.findAncestorStateOfType<_PhotoGalleryScreenState>();
    if (state != null) {
      await state._loadAllTags();
      await state._applyFilters();
    }
  }

  Future<void> _removeTag(String tag) async {
    if (_photoKey == null) return;
    await TagService.removeTag(_photoKey!, tag);
    setState(() {
      _tags.remove(tag);
    });

    // Notify parent to refresh tags and filters
    final state = context.findAncestorStateOfType<_PhotoGalleryScreenState>();
    if (state != null) {
      await state._loadAllTags();
      await state._applyFilters();
    }
  }

  Future<void> _showAddTagDialog() async {
    _tagController.clear();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          autofocus: true,
          controller: _tagController,
          decoration: const InputDecoration(
            hintText: 'Enter tag name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final tag = _tagController.text.trim();
              if (tag.isNotEmpty) {
                Navigator.of(context).pop(tag);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (tag != null && tag.trim().isNotEmpty) {
      await _addTag(tag);
    }
  }

  Future<void> _deletePhoto(BuildContext context) async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text(
          'Are you sure you want to delete this photo? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete tags if photo key is available
      if (_photoKey != null) {
        await TagService.deleteAllTags(_photoKey!);
      }

      // Delete the photo
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds([
        widget.asset.id,
      ]);

      if (deletedIds.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Pop back to gallery and refresh
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            color: Colors.white,
            onPressed: _showAddTagDialog,
            tooltip: 'Add tag',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.white,
            onPressed: () => _deletePhoto(context),
            tooltip: 'Delete photo',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: FutureBuilder<File?>(
                future: widget.asset.file,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return InteractiveViewer(
                      child: Image.file(snapshot.data!, fit: BoxFit.contain),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Text(
                      'Error loading image',
                      style: TextStyle(color: Colors.white),
                    );
                  }
                  return const CircularProgressIndicator(color: Colors.white);
                },
              ),
            ),
          ),
          // Tags section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tags:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                      ),
                      onPressed: _showAddTagDialog,
                      tooltip: 'Add tag',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoadingKey)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else if (_tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'No tags',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.map((tag) {
                      return Chip(
                        label: Text(tag),
                        backgroundColor: Colors.blue[700],
                        labelStyle: const TextStyle(color: Colors.white),
                        deleteIcon: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                        onDeleted: () => _removeTag(tag),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
