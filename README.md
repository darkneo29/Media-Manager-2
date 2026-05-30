# Dragon Media Manager

A native iOS app for managing your self-hosted media server stack. Control your Radarr, Sonarr, and SabNZB servers from anywhere.

![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### Dashboard
- Browse trending movies and TV shows from TMDB
- View upcoming releases in your library
- Quick-add trending content to your library with one tap
- See recently added items at a glance

### Movie Management (Radarr)
- View your complete movie library
- Search and add new movies
- Monitor/unmonitor movies
- View movie details including release dates and runtime
- Delete movies from your library

### TV Show Management (Sonarr)
- View your complete TV show library
- Search and add new shows with quality profile selection
- Choose monitoring options (All Seasons, First Season, Latest Season, None)
- View show details including seasons, episodes, and network info
- Edit quality profiles and monitoring status

### Download Management (SabNZB)
- Real-time download queue monitoring
- View download progress, speed, and ETA
- Pause/resume individual downloads or entire queue
- Access download history
- Clear completed downloads

### Calendar
- Monthly calendar view of upcoming releases
- Movie releases (theatrical, digital, physical)
- TV episode air dates
- Quick navigation to item details

### Additional Features
- Dark theme throughout
- Settings backup and restore
- Connection testing for all services
- Troubleshooting logs viewer for Radarr/Sonarr

## Requirements

This app requires you to have your own self-hosted servers:

| Service | Purpose | Required |
|---------|---------|----------|
| [Radarr](https://radarr.video/) | Movie management | Optional |
| [Sonarr](https://sonarr.tv/) | TV show management | Optional |
| [SabNZB](https://sabnzbd.org/) | Download client | Optional |
| [TMDB API](https://www.themoviedb.org/documentation/api) | Trending content & metadata | Optional |

You need at least one service configured to use the app. Each service requires:
- Server URL (e.g., `http://radarr.local:7878`)
- API Key (found in each service's settings)

## Installation

### TestFlight
Coming soon.

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/darkneo29/Media-Manager-2.git
   ```

2. Open the project in Xcode:
   ```bash
   cd Media-Manager-2
   open "Media Manager.xcodeproj"
   ```

3. Select your target device or simulator

4. Build and run (⌘R)

## Configuration

1. Open the app and navigate to **Settings**
2. Configure each service you want to use:
   - **Radarr Settings** - Enter your Radarr URL and API key
   - **Sonarr Settings** - Enter your Sonarr URL and API key
   - **SabNZB Settings** - Enter your SabNZB URL and API key
   - **TMDB Settings** - Enter your TMDB Read Access Token
3. Use **Test Connection** to verify each configuration
4. Return to the main tabs to start managing your media

### Finding Your API Keys

- **Radarr/Sonarr**: Settings → General → API Key
- **SabNZB**: Config → General → API Key
- **TMDB**: Account Settings → API → Read Access Token (v4 auth)

## Privacy

- All configuration data is stored locally on your device
- The app only communicates with your self-hosted servers and TMDB
- No analytics or tracking
- No data is sent to the developer

## Security

This repository does not include API keys, server credentials, Apple signing credentials, provisioning profiles, or personal service configuration. Users configure their own Radarr, Sonarr, SABnzbd, Unraid, and TMDB credentials locally on-device.

## Tech Stack

- **UI Framework**: SwiftUI
- **Minimum iOS**: 17.0
- **Architecture**: MVVM-lite with singleton services
- **Networking**: Native URLSession with async/await
- **Storage**: UserDefaults for configuration

## Attribution

This product uses the TMDB API but is not endorsed or certified by TMDB.

[![TMDB](https://www.themoviedb.org/assets/2/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg)](https://www.themoviedb.org/)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

GitHub: [@darkneo29](https://github.com/darkneo29)
