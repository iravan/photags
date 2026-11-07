# PhoTags

A local-first Flutter photo gallery. Tag your device photos, filter by those tags, and keep everything on-device — no cloud, no accounts.

## Features

- Browse device photos in a dark-themed grid
- Create custom tags and apply multiple tags per photo
- Filter the gallery by one or more tags (OR logic)
- Multi-select and bulk-delete photos (including drag-to-select)
- Export / import tags as YAML for backup
- Full-screen viewer with pinch zoom and swipe navigation

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) (SDK `^3.10.4`)
- Photo library permission on the device (iOS / Android)

## Run

```bash
flutter pub get
flutter run
```

Build for a specific platform:

```bash
flutter run -d ios
flutter run -d android
flutter build apk
flutter build ipa
```

## Project structure

```
lib/
  main.dart              # App UI (gallery, viewer, selection, filters)
  tag_service.dart       # Tag storage, index, export/import
  dialog_helpers.dart    # Shared dialogs
  constants/             # Colors, strings, dimensions, typography
```

Tags are stored locally with `shared_preferences`. Photos are keyed by `{width}_{height}_{createTime}` so tags survive gallery reloads. A reverse tag index powers fast filtering.

## Privacy

All photos and tags stay on the device. PhoTags does not sync, upload, or collect data.

## License

Private / unpublished (`publish_to: 'none'` in `pubspec.yaml`).
