class AppStrings {
  // App info
  static const String appTitle = 'PhoTags - Photo Gallery';

  // Permission messages
  static const String permissionDenied =
      'Permission denied. Please grant photo access permission in settings.';
  static const String noPhotosFound = 'No photos found on device.';
  static const String errorRequestingPermission =
      'Error requesting permission: ';

  // Loading messages
  static const String loadingPhotos = 'Loading photos...';
  static const String errorLoadingPhotos = 'Error loading photos: ';

  // Filter section
  static const String filterByTags = 'Filter by tags:';

  // Selection mode
  static const String photosSelected = 'photo(s) selected';
  static const String delete = 'Delete';

  // Photo viewer
  static const String allTags = 'All Tags:';
  static const String addTag = 'Add Tag';
  static const String editTag = 'Edit Tag';
  static const String enterTagName = 'Enter tag name';
  static const String enterNewTagName = 'Enter new tag name';
  static const String deleteTagConfirm =
      'Are you sure you want to delete this tag? This will remove it from all photos.';
  static const String cancel = 'Cancel';
  static const String add = 'Add';
  static const String edit = 'Save';

  // Delete messages
  static const String deletePhoto = 'Delete Photo';
  static const String deletePhotos = 'Delete Photos';
  static const String deletePhotoConfirm =
      'Are you sure you want to delete this photo? This action cannot be undone.';
  static const String deletePhotosConfirm =
      'Are you sure you want to delete {count} photo(s)? This action cannot be undone.';
  static const String photoDeletedSuccessfully = 'Photo deleted successfully';
  static const String photosDeletedSuccessfully =
      '{count} photo(s) deleted successfully';
  static const String errorDeletingPhoto = 'Error deleting photo: ';
  static const String errorDeletingPhotos = 'Error deleting photos: ';

  // File operations
  static const String openInFileViewer = 'Open in file viewer';
  static const String unableToOpenPhoto = 'Unable to open photo';
  static const String unableToOpenFile = 'Unable to open file: ';
  static const String errorOpeningFile = 'Error opening file: ';

  // Error messages
  static const String errorLoadingImage = 'Error loading image';
  static const String noTagsApplied = 'No tags applied';

  // Tooltips
  static const String tooltipAddTag = 'Add tag';
  static const String tooltipDeletePhoto = 'Delete photo';

  // Help
  static const String help = 'Help';
  static const String helpTitle = 'How to Use PhoTags';

  // Export/Import
  static const String exportTags = 'Export Tags';
  static const String importTags = 'Import Tags';
  static const String exportTagsSuccess = 'Tags exported successfully';
  static const String exportTagsError = 'Error exporting tags: ';
  static const String importTagsSuccess = 'Tags imported successfully';
  static const String importTagsError = 'Error importing tags: ';
  static const String importTagsConfirm =
      'Importing tags will replace all existing tags. Continue?';
  static const String importTagsConfirmTitle = 'Confirm Import';
  static const String helpViewingPhotos = 'Viewing Photos';
  static const String helpViewingPhotosDesc =
      '• Tap any photo to view it in full screen\n'
      '• Pinch to zoom in/out or double-tap to zoom\n'
      '• Swipe left/right to navigate between photos\n'
      '• Use the back button to return to the gallery';
  static const String helpSelectingPhotos = 'Selecting & Deleting Photos';
  static const String helpSelectingPhotosDesc =
      '• Tap the select icon (☑) in the top-right to enter selection mode\n'
      '• Tap photos to select/deselect them\n'
      '• Use the delete button to remove selected photos\n'
      '• Tap the X button to exit selection mode';
  static const String helpTagging = 'Tagging Photos';
  static const String helpTaggingDesc =
      '• Open a photo in full screen\n'
      '• Scroll down to see "All Tags" section\n'
      '• Tap "Add Tag" to create a new tag\n'
      '• Tap existing tags to add/remove them from the photo\n'
      '• Long-press a tag to edit or delete it';
  static const String helpFiltering = 'Filtering by Tags';
  static const String helpFilteringDesc =
      '• Tags appear at the top of the photo gallery\n'
      '• Tap tags to filter photos (shows photos with ANY selected tag)\n'
      '• Tap again to deselect and show all photos\n'
      '• Long-press a tag to edit or delete it';
  static const String helpOtherFeatures = 'Other Features';
  static const String helpOtherFeaturesDesc =
      '• Use the refresh button (↻) to reload photos\n'
      '• Tap "Open in file viewer" to view photo in system app\n'
      '• Scroll position is saved when navigating between screens';

  // Helper method for pluralization
  static String deletePhotosConfirmWithCount(int count) {
    return deletePhotosConfirm.replaceAll('{count}', count.toString());
  }

  static String photosDeletedSuccessfullyWithCount(int count) {
    return photosDeletedSuccessfully.replaceAll('{count}', count.toString());
  }
}
