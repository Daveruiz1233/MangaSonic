# MangaSonic

MangaSonic is a simple, ultra-fast manga and manhua reader app built in Flutter/Dart, targeting iOS 15+ and Android 8+. Its primary goal is to provide maximum performance for reading manga, completely devoid of heavy abstraction layers or extension systems.

## Features
- **Extremely Fast Image Loading:** Minimized latency with aggressive image prefetching, caching, and concurrent HTTP requests.
- **Library Screen & Categories:** Users can save their favorite manga into custom categories (e.g., "Favorites", "Action") managed entirely offline via SQLite/Hive.
- **Offline First:** A strict offline reading policy ensures that once a chapter is downloaded, local images are exclusively loaded without any network fallback, eliminating connection timeouts during reading.
- **Downloads Manager:** Full control over chapter downloads, background fetching, and file storage.
- **Three Supported Sites (Hardcoded Parsers):**
  - [ManhuaTop](https://manhuatop.org/)
  - [AsuraComic](https://asuracomic.net/)
  - [ManhuaPlus](https://manhuaplus.com/)

## Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- Supported targets: Android 8+ (API level 26+) and iOS 15+

### Build & Run
```bash
flutter clean
flutter pub get
flutter run
```

## Folder Structure
```text
manga_sonic/
├── lib/
│   ├── ui/        # Screens, widgets, and themes (Material & Cupertino)
│   ├── data/      # Models, DB logic, and storage via path_provider
│   ├── parser/    # Hardcoded HTML parsers for manhuatop, asuracomic, manhuaplus
│   ├── cache/     # Specialized aggressive image caching and look-ahead
│   └── utils/     # Helpers and common logic
```

## Architecture & Performance Strategies

MangaSonic ditches a complicated extension architecture to hardcode robust parsers for its 3 supported sites. This prevents abstraction overhead.

### Image Loading Policies
- **Concurrent Networking:** Leverages persistent HTTP clients with batch processing and `gzip/deflate` support explicitly enabled.
- **Disk & Memory Caching:** Uses tuned LRU disk caches and heavily clamped memory caching boundaries. Unseen images are disposed of proactively.
- **Prefetching:** Looks ahead of the scroll boundary to load low-res variations first if possible, transitioning rapidly to high-res. 
- **Strict Offline Policy:** Network images are bypassed automatically if the database confirms a chapter is downloaded. Reader views will solely use `Image.file()`, removing networking completely.

## Contribution
Contributions are welcome. Please ensure that PRs respect the core tenets of the app: minimal abstractions, maximum speed, and maintaining offline-first integrity for downloaded reading.
