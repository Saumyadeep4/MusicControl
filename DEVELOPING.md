# Developing MusicControl

Notes for anyone who wants to build MusicControl from source or contribute.

## Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/Saumyadeep4/MusicControl.git
   cd MusicControl
   ```
2. Open the `.xcodeproj` file in Xcode.
3. In **Signing & Capabilities**, choose your own Team (a free Apple ID works).
4. Make sure **App Sandbox** is not enabled. If **Hardened Runtime** is on, tick **Apple Events** under Resource Access.
5. In the **Info** tab, make sure these entries exist:
   - `Privacy - AppleEvents Sending Usage Description`
   - `Application is agent (UIElement)` set to `YES`
6. Press **Command+R** to build and run.

## Project structure

| File | Purpose |
| --- | --- |
| `MyApp.swift` | App entry point and the menu bar item |
| `PlayerStore.swift` | Reads the current track from Apple Music and sends playback commands via AppleScript |
| `ContentView.swift` | The menu bar popover UI |
| `Notch.swift` | The notch window, hover detection and notch UI |

## How it works

- `PlayerStore` polls Apple Music about once per second through AppleScript and publishes the result to the SwiftUI views.
- Artwork is only reloaded when the track changes.
- The notch is a borderless, transparent `NSPanel` positioned at the top centre of the screen. A timer checks the cursor position and expands or collapses the card.
- Settings are stored with `@AppStorage` (`showSongInMenuBar`, `showArtInMenuBar`, `showNotch`).

## Making a release build

1. Choose **Product > Scheme > Edit Scheme**, select **Run**, and set **Build Configuration** to **Release**.
2. Build with **Command+B**, then open **Product > Show Build Folder in Finder** and find the app under **Products > Release**.
3. Zip it in a way that keeps the signature intact:
   ```bash
   ditto -c -k --keepParent MusicControl.app MusicControl.zip
   ```
4. Attach the zip to a new GitHub Release.

## Roadmap

- [ ] Spotify support
- [ ] YouTube Music support
- [ ] Launch at login
- [ ] Notarized builds

## Contributing

Issues and pull requests are welcome. For larger changes, please open an issue first to discuss the idea.
