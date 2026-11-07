import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'tag_service.dart';
import 'constants/colors.dart';
import 'constants/strings.dart';
import 'constants/dimensions.dart';
import 'constants/typography.dart';
import 'dialog_helpers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
            ).copyWith(
              primary: AppColors.primary,
              secondary: AppColors.secondary,
              surface: AppColors.primary,
              background: AppColors.primary,
            ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textWhite,
        ),
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

  // Scroll position tracking
  final ScrollController _scrollController = ScrollController();
  double _savedScrollPosition = 0.0;

  // Tag editing controller
  final TextEditingController _editTagController = TextEditingController();

  // Drag-to-select state
  bool _isDraggingToSelect = false;
  Set<String> _photosBeingDraggedOver = {};

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
    _scrollController.dispose();
    _editTagController.dispose();
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

  Future<void> _showEditTagDialog(String oldTag) async {
    _editTagController.text = oldTag;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.editTag,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              controller: _editTagController,
              style: const TextStyle(color: AppColors.textWhite),
              cursorColor: AppColors.textWhite,
              decoration: DialogHelpers.buildTextFieldDecoration(
                hintText: AppStrings.enterNewTagName,
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty && value.trim() != oldTag) {
                  Navigator.of(
                    context,
                  ).pop({'action': 'edit', 'tag': value.trim()});
                }
              },
            ),
            const SizedBox(height: AppDimensions.spacingM),
            DialogHelpers.buildDeleteTagButton(
              context,
              () => Navigator.of(context).pop({'action': 'delete'}),
            ),
          ],
        ),
        actions: [
          DialogHelpers.buildCancelButton(context),
          TextButton(
            onPressed: () {
              final tag = _editTagController.text.trim();
              if (tag.isNotEmpty && tag != oldTag) {
                Navigator.of(context).pop({'action': 'edit', 'tag': tag});
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text(AppStrings.edit),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result['action'] == 'delete') {
        // Delete tag from all photos
        await TagService.deleteTag(oldTag);

        // Update local state
        setState(() {
          _selectedFilterTags.remove(oldTag);
          _allTags.remove(oldTag);
        });

        // Refresh filters and tags
        await _loadAllTags();
        await _applyFilters();
      } else if (result['action'] == 'edit') {
        final newTag = result['tag'] as String;
        if (newTag.trim().isNotEmpty && newTag != oldTag) {
          await TagService.renameTag(oldTag, newTag);

          // Update local state
          setState(() {
            if (_selectedFilterTags.contains(oldTag)) {
              _selectedFilterTags.remove(oldTag);
              _selectedFilterTags.add(newTag);
            }
            _allTags.remove(oldTag);
            _allTags.add(newTag);
          });

          // Refresh filters and tags
          await _loadAllTags();
          await _applyFilters();
        }
      }
    }
    _editTagController.clear();
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.helpTitle,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStrings.helpViewingPhotos,
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: AppTypography.fontWeightBold,
                  fontSize: AppTypography.fontSizeL,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXS),
              Text(
                AppStrings.helpViewingPhotosDesc,
                style: const TextStyle(
                  color: AppColors.textWhite70,
                  fontSize: AppTypography.fontSizeM,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              const Text(
                AppStrings.helpSelectingPhotos,
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: AppTypography.fontWeightBold,
                  fontSize: AppTypography.fontSizeL,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXS),
              Text(
                AppStrings.helpSelectingPhotosDesc,
                style: const TextStyle(
                  color: AppColors.textWhite70,
                  fontSize: AppTypography.fontSizeM,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              const Text(
                AppStrings.helpTagging,
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: AppTypography.fontWeightBold,
                  fontSize: AppTypography.fontSizeL,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXS),
              Text(
                AppStrings.helpTaggingDesc,
                style: const TextStyle(
                  color: AppColors.textWhite70,
                  fontSize: AppTypography.fontSizeM,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              const Text(
                AppStrings.helpFiltering,
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: AppTypography.fontWeightBold,
                  fontSize: AppTypography.fontSizeL,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXS),
              Text(
                AppStrings.helpFilteringDesc,
                style: const TextStyle(
                  color: AppColors.textWhite70,
                  fontSize: AppTypography.fontSizeM,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              const Text(
                AppStrings.helpOtherFeatures,
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: AppTypography.fontWeightBold,
                  fontSize: AppTypography.fontSizeL,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXS),
              Text(
                AppStrings.helpOtherFeaturesDesc,
                style: const TextStyle(
                  color: AppColors.textWhite70,
                  fontSize: AppTypography.fontSizeM,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTags() async {
    try {
      // Generate YAML content
      final yamlContent = await TagService.exportTagsToYamlString();

      // Generate default filename with timestamp
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final defaultFileName = 'photags_tags_$timestamp.yaml';

      // Convert string to bytes for Android/iOS
      final bytes = utf8.encode(yamlContent);

      // Let user choose save location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: AppStrings.exportTags,
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
        bytes: bytes,
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStrings.exportTagsSuccess}\n$result',
                style: const TextStyle(color: AppColors.snackbarText),
              ),
              backgroundColor: AppColors.snackbarBackground,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.exportTagsError}$e',
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
      }
      debugPrint('Error exporting tags: $e');
    }
  }

  Future<void> _importTags() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.importTagsConfirmTitle,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          AppStrings.importTagsConfirm,
          style: TextStyle(color: AppColors.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.whiteWithOpacity(0.7),
            ),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text(AppStrings.importTags),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Pick YAML file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        await TagService.importTagsFromYaml(filePath);

        // Refresh tags and filters
        await _loadAllTags();
        await _applyFilters();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppStrings.importTagsSuccess,
                style: const TextStyle(color: AppColors.snackbarText),
              ),
              backgroundColor: AppColors.snackbarBackground,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.importTagsError}$e',
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
      }
      debugPrint('Error importing tags: $e');
    }
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
          _errorMessage = AppStrings.permissionDenied;
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
          _errorMessage = AppStrings.noPhotosFound;
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

      // Restore scroll position after loading if available
      if (_savedScrollPosition > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _savedScrollPosition > 0) {
            _scrollController.jumpTo(_savedScrollPosition);
            _savedScrollPosition = 0.0;
          }
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '${AppStrings.errorLoadingPhotos}$e';
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

  void _handleDragOverPhoto(Offset localPosition, List<AssetEntity> photos) {
    if (!_isSelectionMode || photos.isEmpty) return;

    // Account for padding
    final padding = AppDimensions.gridSpacing;
    final gridSpacing = AppDimensions.gridSpacing;

    // Calculate grid cell size
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - (padding * 2);
    final cellWidth =
        (availableWidth -
            gridSpacing * (AppDimensions.gridCrossAxisCount - 1)) /
        AppDimensions.gridCrossAxisCount;
    final cellHeight = cellWidth; // Square cells

    // Adjust position for padding and scroll offset
    final adjustedX = localPosition.dx - padding;
    final adjustedY = localPosition.dy - padding + _scrollController.offset;

    // Calculate which grid cell the position is in
    final column = (adjustedX / (cellWidth + gridSpacing)).floor();
    final row = (adjustedY / (cellHeight + gridSpacing)).floor();
    final index = row * AppDimensions.gridCrossAxisCount + column;

    // Check if index is valid and photo hasn't been processed yet
    if (index >= 0 && index < photos.length) {
      final photoId = photos[index].id;
      if (!_photosBeingDraggedOver.contains(photoId)) {
        _photosBeingDraggedOver.add(photoId);
        // Add to selection if not already selected
        final currentSelection = Set<String>.from(_selectedPhotoIds);
        if (!currentSelection.contains(photoId)) {
          currentSelection.add(photoId);
          _selectedPhotoIdsNotifier.value = currentSelection;
        }
      }
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotoIds.isEmpty) return;

    // Skip confirmation dialog on iOS since system already prompts
    if (!Platform.isIOS) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.deletePhotos),
          content: Text(
            AppStrings.deletePhotosConfirmWithCount(_selectedPhotoIds.length),
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
    }

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

      // Restore scroll position after deletion
      if (_savedScrollPosition > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _savedScrollPosition > 0) {
            _scrollController.jumpTo(_savedScrollPosition);
            _savedScrollPosition = 0.0;
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.photosDeletedSuccessfullyWithCount(deletedIds.length),
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.errorDeletingPhotos}$e',
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            tooltip: AppStrings.help,
            onSelected: (value) {
              if (value == 'help') {
                _showHelpDialog();
              } else if (value == 'export') {
                _exportTags();
              } else if (value == 'import') {
                _importTags();
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];

              // Only show export if there are tags
              if (_allTags.isNotEmpty) {
                items.add(
                  const PopupMenuItem<String>(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(
                          Icons.file_download,
                          size: AppDimensions.iconSizeM,
                        ),
                        SizedBox(width: AppDimensions.spacingS),
                        Text(AppStrings.exportTags),
                      ],
                    ),
                  ),
                );
              }

              items.add(
                const PopupMenuItem<String>(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload, size: AppDimensions.iconSizeM),
                      SizedBox(width: AppDimensions.spacingS),
                      Text(AppStrings.importTags),
                    ],
                  ),
                ),
              );

              // Only add divider if export was shown
              if (_allTags.isNotEmpty) {
                items.add(const PopupMenuDivider());
              }

              items.add(
                const PopupMenuItem<String>(
                  value: 'help',
                  child: Row(
                    children: [
                      Icon(Icons.help_outline, size: AppDimensions.iconSizeM),
                      SizedBox(width: AppDimensions.spacingS),
                      Text(AppStrings.help),
                    ],
                  ),
                ),
              );

              return items;
            },
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
            SizedBox(height: AppDimensions.spacingL),
            Text('Loading photos...'),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: AppDimensions.iconSizeXXL,
                color: AppColors.textGrey,
              ),
              const SizedBox(height: 16),
              const Text(
                'Photo Access Permission Required',
                style: AppTypography.headingLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingXL),
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
          padding: const EdgeInsets.all(AppDimensions.paddingXL),
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
              const SizedBox(height: AppDimensions.spacingXL),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: AppDimensions.iconSizeXXL,
              color: AppColors.textGrey,
            ),
            SizedBox(height: AppDimensions.spacingL),
            Text(
              AppStrings.noPhotosFound,
              style: AppTypography.withColor(
                AppTypography.bodyLarge.copyWith(
                  fontSize: AppTypography.fontSizeXXL,
                ),
                AppColors.textGrey,
              ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingS,
              vertical: AppDimensions.spacingS,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.filterByTags,
                  style: AppTypography.headingSmall,
                ),
                const SizedBox(height: AppDimensions.spacingS),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _allTags.map((tag) {
                    final isSelected = _selectedFilterTags.contains(tag);
                    return GestureDetector(
                      onLongPress: () => _showEditTagDialog(tag),
                      child: ActionChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.label_outline,
                              size: 14,
                              color: isSelected
                                  ? const Color(0xFF191921)
                                  : const Color(
                                      0xffacafbf,
                                    ).withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: AppDimensions.tagIconSpacing),
                            Text(tag),
                          ],
                        ),
                        backgroundColor: isSelected
                            ? Colors
                                  .white // Bootstrap badge: white background
                            : Colors.transparent, // Outlined style for inactive
                        side: BorderSide(
                          color: isSelected
                              ? Colors
                                    .white // No visible border (matches bg)
                              : const Color(
                                  0xffacafbf,
                                ).withValues(alpha: 0.5), // Outlined border
                          width: isSelected ? 0 : 1,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.tagBorderRadius,
                          ),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? const Color(
                                  0xFF191921,
                                ) // Primary color (dark) - fully opaque
                              : const Color(0xffacafbf).withValues(
                                  alpha: 0.5,
                                ), // Match border color for inactive
                          fontWeight:
                              FontWeight.w500, // Bootstrap badge: medium weight
                          fontSize: AppTypography.fontSizeS,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.tagHorizontalPadding,
                          vertical: AppDimensions.tagVerticalPadding,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleFilterTag(tag),
                      ),
                    );
                  }).toList(),
                ),
                if (_selectedFilterTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppDimensions.spacingS),
                    child: Text(
                      'Showing ${_filteredPhotos.length} of ${_photos.length} photos',
                      style: TextStyle(
                        fontSize: AppTypography.fontSizeS,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
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
                      const SizedBox(height: AppDimensions.spacingS),
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

                    // Restore scroll position if available (will be handled after navigation returns)

                    return Container(
                      color: Colors.white,
                      child: GestureDetector(
                        onPanStart: _isSelectionMode
                            ? (details) {
                                _isDraggingToSelect = true;
                                _photosBeingDraggedOver.clear();
                                _handleDragOverPhoto(
                                  details.localPosition,
                                  photosToShow,
                                );
                              }
                            : null,
                        onPanUpdate: _isSelectionMode
                            ? (details) {
                                _handleDragOverPhoto(
                                  details.localPosition,
                                  photosToShow,
                                );
                              }
                            : null,
                        onPanEnd: _isSelectionMode
                            ? (_) {
                                _isDraggingToSelect = false;
                                _photosBeingDraggedOver.clear();
                              }
                            : null,
                        onPanCancel: _isSelectionMode
                            ? () {
                                _isDraggingToSelect = false;
                                _photosBeingDraggedOver.clear();
                              }
                            : null,
                        child: GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(
                            AppDimensions.gridSpacing,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    AppDimensions.gridCrossAxisCount,
                                crossAxisSpacing: AppDimensions.gridSpacing,
                                mainAxisSpacing: AppDimensions.gridSpacing,
                              ),
                          itemCount: photosToShow.length,
                          itemBuilder: (context, index) {
                            final asset = photosToShow[index];
                            return RepaintBoundary(
                              key: ValueKey(asset.id),
                              child: _PhotoThumbnail(
                                asset: asset,
                                isSelectionMode: _isSelectionMode,
                                selectedPhotoIdsNotifier:
                                    _selectedPhotoIdsNotifier,
                                onTap: _isSelectionMode && !_isDraggingToSelect
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
                        ),
                      ),
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
                  horizontal: AppDimensions.spacingL,
                  vertical: AppDimensions.spacingS,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
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
                        '${selectedIds.length} ${AppStrings.photosSelected}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ElevatedButton.icon(
                        onPressed: _deleteSelectedPhotos,
                        icon: const Icon(Icons.delete),
                        label: const Text(AppStrings.delete),
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
            decoration: const BoxDecoration(color: Colors.white),
            child: _isLoadingThumbnail
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _thumbnailData != null
                ? Image.memory(
                    _thumbnailData!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  )
                : const Icon(Icons.broken_image, color: Colors.grey),
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
                          : Colors.white.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.paddingXS),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: AppDimensions.iconSizeM,
                            )
                          : const SizedBox(
                              width: AppDimensions.iconSizeM,
                              height: AppDimensions.iconSizeM,
                            ),
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
    // Save current scroll position
    final state = context.findAncestorStateOfType<_PhotoGalleryScreenState>();
    if (state != null && state._scrollController.hasClients) {
      state._savedScrollPosition = state._scrollController.offset;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullImageScreen(asset: widget.asset),
      ),
    );

    // Save scroll position before any async operations
    final savedPosition = state?._savedScrollPosition ?? 0.0;

    // Refresh gallery if photo was deleted or tags were updated
    if (result == true) {
      await state?._refreshPhotos();
    } else {
      // Refresh tags and filters even if photo wasn't deleted
      await state?._loadAllTags();
      await state?._applyFilters();
    }

    // Restore scroll position after all operations complete
    if (state != null && savedPosition > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (state._scrollController.hasClients) {
          state._scrollController.jumpTo(savedPosition);
          state._savedScrollPosition = 0.0;
        }
      });
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
  Set<String> _allExistingTags = {};
  String? _photoKey;
  bool _isLoadingKey = false;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _editTagController = TextEditingController();
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadAllExistingTags();
  }

  @override
  void dispose() {
    _tagController.dispose();
    _editTagController.dispose();
    _transformationController.dispose();
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

  Future<void> _loadAllExistingTags() async {
    final tags = await TagService.getAllUniqueTags();
    setState(() {
      _allExistingTags = tags;
    });
  }

  Future<void> _addTag(String tag) async {
    if (tag.trim().isEmpty || _photoKey == null) return;
    final trimmedTag = tag.trim();
    if (_tags.contains(trimmedTag)) return;

    await TagService.addTag(_photoKey!, trimmedTag);
    setState(() {
      _tags = List.from(_tags)..add(trimmedTag);
      _allExistingTags.add(trimmedTag); // Add to existing tags if new
    });
    _tagController.clear();

    // Notify parent to refresh tags and filters
    final state = context.findAncestorStateOfType<_PhotoGalleryScreenState>();
    if (state != null) {
      await state._loadAllTags();
      await state._applyFilters();
    }
  }

  Future<void> _toggleTagFromExisting(String tag) async {
    if (_tags.contains(tag)) {
      // Remove tag if already applied
      await _removeTag(tag);
    } else {
      // Add tag if not applied
      await _addTag(tag);
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
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.addTag,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: TextField(
          autofocus: true,
          controller: _tagController,
          style: const TextStyle(color: AppColors.textWhite),
          cursorColor: AppColors.textWhite,
          decoration: DialogHelpers.buildTextFieldDecoration(
            hintText: AppStrings.enterTagName,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          DialogHelpers.buildCancelButton(context),
          TextButton(
            onPressed: () {
              final tag = _tagController.text.trim();
              if (tag.isNotEmpty) {
                Navigator.of(context).pop(tag);
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text(AppStrings.add),
          ),
        ],
      ),
    );

    if (tag != null && tag.trim().isNotEmpty) {
      await _addTag(tag);
    }
  }

  Future<void> _showEditTagDialog(String oldTag) async {
    _editTagController.text = oldTag;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.editTag,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              controller: _editTagController,
              style: const TextStyle(color: AppColors.textWhite),
              cursorColor: AppColors.textWhite,
              decoration: DialogHelpers.buildTextFieldDecoration(
                hintText: AppStrings.enterNewTagName,
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty && value.trim() != oldTag) {
                  Navigator.of(
                    context,
                  ).pop({'action': 'edit', 'tag': value.trim()});
                }
              },
            ),
            const SizedBox(height: AppDimensions.spacingM),
            DialogHelpers.buildDeleteTagButton(
              context,
              () => Navigator.of(context).pop({'action': 'delete'}),
            ),
          ],
        ),
        actions: [
          DialogHelpers.buildCancelButton(context),
          TextButton(
            onPressed: () {
              final tag = _editTagController.text.trim();
              if (tag.isNotEmpty && tag != oldTag) {
                Navigator.of(context).pop({'action': 'edit', 'tag': tag});
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text(AppStrings.edit),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result['action'] == 'delete') {
        // Delete tag from all photos
        await TagService.deleteTag(oldTag);

        // Update local state
        setState(() {
          _tags.remove(oldTag);
          _allExistingTags.remove(oldTag);
        });

        // Notify parent to refresh tags and filters
        final state = context
            .findAncestorStateOfType<_PhotoGalleryScreenState>();
        if (state != null) {
          await state._loadAllTags();
          await state._applyFilters();
        }
      } else if (result['action'] == 'edit') {
        final newTag = result['tag'] as String;
        if (newTag.trim().isNotEmpty && newTag != oldTag) {
          await TagService.renameTag(oldTag, newTag);

          // Update local state
          setState(() {
            if (_tags.contains(oldTag)) {
              _tags.remove(oldTag);
              _tags.add(newTag);
            }
            if (_allExistingTags.contains(oldTag)) {
              _allExistingTags.remove(oldTag);
              _allExistingTags.add(newTag);
            }
          });

          // Notify parent to refresh tags and filters
          final state = context
              .findAncestorStateOfType<_PhotoGalleryScreenState>();
          if (state != null) {
            await state._loadAllTags();
            await state._applyFilters();
          }
        }
      }
    }
    _editTagController.clear();
  }

  Future<void> _openInSystemPhotos() async {
    try {
      // Get the photo file
      final file = await widget.asset.file;
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                AppStrings.unableToOpenPhoto,
                style: const TextStyle(color: AppColors.snackbarText),
              ),
              backgroundColor: AppColors.snackbarBackground,
            ),
          );
        }
        return;
      }

      // Open file using open_file package - opens with default app
      final result = await OpenFile.open(file.path);

      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStrings.unableToOpenFile}${result.message}',
                style: const TextStyle(color: AppColors.snackbarText),
              ),
              backgroundColor: AppColors.snackbarBackground,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.errorOpeningFile}$e',
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
      }
      debugPrint('Error opening file: $e');
    }
  }

  Future<void> _deletePhoto(BuildContext context) async {
    // Skip confirmation dialog on iOS since system already prompts
    if (!Platform.isIOS) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.deletePhoto),
          content: const Text(AppStrings.deletePhotoConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text(AppStrings.delete),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

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
            content: Text(
              AppStrings.photoDeletedSuccessfully,
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
          ),
        );
        // Pop back to gallery and refresh
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.errorDeletingPhoto}$e',
              style: const TextStyle(color: AppColors.snackbarText),
            ),
            backgroundColor: AppColors.snackbarBackground,
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
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            color: Colors.white,
            onPressed: _openInSystemPhotos,
            tooltip: 'Open in file viewer',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.white,
            onPressed: () => _deletePhoto(context),
            tooltip: AppStrings.tooltipDeletePhoto,
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
                      transformationController: _transformationController,
                      child: Image.file(snapshot.data!, fit: BoxFit.contain),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Text(
                      AppStrings.errorLoadingImage,
                      style: TextStyle(color: Colors.white),
                    );
                  }
                  return const CircularProgressIndicator(color: Colors.white);
                },
              ),
            ),
          ),
          // Tags section
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,

              padding: const EdgeInsets.all(AppDimensions.spacingL),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // All Tags section - always show
                    Text(
                      AppStrings.allTags,
                      style: AppTypography.withColor(
                        AppTypography.headingSmall,
                        AppColors.textWhite70,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),
                    Wrap(
                      spacing: AppDimensions.tagSpacing,
                      runSpacing: AppDimensions.tagSpacing,
                      children: [
                        // Existing tags - only show if there are any
                        ..._allExistingTags.map((tag) {
                          final isApplied = _tags.contains(tag);
                          return GestureDetector(
                            onLongPress: () => _showEditTagDialog(tag),
                            child: ActionChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.label_outline,
                                    size: 14,
                                    color: isApplied
                                        ? const Color(0xFF191921)
                                        : const Color(
                                            0x77acafbf,
                                          ).withValues(alpha: 1.0),
                                  ),
                                  const SizedBox(
                                    width: AppDimensions.tagIconSpacing,
                                  ),
                                  Text(tag),
                                ],
                              ),
                              backgroundColor: isApplied
                                  ? Colors
                                        .white // Bootstrap badge: white background
                                  : Colors
                                        .transparent, // Outlined style for inactive
                              side: BorderSide(
                                color: isApplied
                                    ? Colors
                                          .white // No visible border (matches bg)
                                    : const Color(
                                        0x77acafbf,
                                      ), // Outlined border
                                width: isApplied ? 0 : 1,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.tagBorderRadius,
                                ),
                              ),
                              labelStyle: TextStyle(
                                color: isApplied
                                    ? const Color(
                                        0xFF191921,
                                      ) // Primary color (dark) - fully opaque
                                    : const Color(0x77acafbf).withValues(
                                        alpha: 1.0,
                                      ), // Match border color for inactive
                                fontWeight: FontWeight
                                    .w500, // Bootstrap badge: medium weight
                                fontSize: AppTypography.fontSizeS,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _toggleTagFromExisting(tag),
                            ),
                          );
                        }),
                        // Add tag button - always show
                        ActionChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add,
                                size: 14,
                                color: const Color(
                                  0xffacafbf,
                                ).withValues(alpha: 0.5),
                              ),
                              const SizedBox(
                                width: AppDimensions.tagIconSpacing,
                              ),
                              const Text(AppStrings.addTag),
                            ],
                          ),
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimensions.tagBorderRadius,
                            ),
                          ),
                          labelStyle: TextStyle(
                            color: const Color(
                              0xffacafbf,
                            ).withValues(alpha: 0.5),
                            fontWeight: AppTypography.fontWeightMedium,
                            fontSize: AppTypography.fontSizeS,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _showAddTagDialog,
                        ),
                      ],
                    ),
                    if (_isLoadingKey)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
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
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
