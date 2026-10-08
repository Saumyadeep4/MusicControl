# MusicControl

A lightweight macOS menu bar app for controlling your music, with a hover-to-reveal player in the notch.

MusicControl lives in your menu bar (no Dock icon). It shows what's playing, lets you control playback from a popover, and expands a mini player out of the MacBook notch when you move your cursor onto it.

<!-- Add screenshots here once you have them:
![Popover](screenshots/popover.png)
![Notch](screenshots/notch.png)
-->

## Features

- **Menu bar display**: show the album cover, the song name, both, or just an icon. Each is a toggle in settings.
- **Popover player**: large album art with a colour wash taken from the cover, title, artist, album, playlist, a scrubbable progress bar, and playback controls.
- **Notch player**: move your cursor onto the notch and a player card expands from it. Move away and it tucks back in.
- **Scrubbing**: drag the progress bar in the popover or the notch card to jump to any point in the song.
- **Remembers your settings** between launches.

## Supported players

| Player | Status |
| --- | --- |
| Apple Music | Supported |
| Spotify | Planned |
| YouTube Music | Planned |

## Requirements

- macOS 14 (Sonoma) or later
- Apple Music app
- A MacBook with a notch for the full notch experience. The menu bar popover works on any Mac.

## Install

1. Download the latest `MusicControl.zip` from the [Releases](../../releases) page.
2. Unzip it and drag **MusicControl** into your **Applications** folder.
3. Open it. Because the app isn't notarized by Apple, macOS will block the first launch:
   - Open **System Settings > Privacy & Security**.
   - Scroll down and click **Open Anyway** next to the MusicControl message.
4. When macOS asks whether MusicControl can control **Music**, click **OK**. The app needs this to read the current song and send play, pause and skip commands.

### If macOS says the app is "damaged"

This happens with downloaded apps that aren't notarized. Remove the quarantine flag once in Terminal:

```bash
xattr -cr /Applications/MusicControl.app
```

### If the app says "Nothing playing" while music is playing

The Music permission is probably missing. Open **System Settings > Privacy & Security > Automation**, find MusicControl, and make sure **Music** is switched on. You can also reset permissions and relaunch:

```bash
tccutil reset AppleEvents
```

## Usage

- Click the menu bar icon to open the popover.
- Click the gear icon in the popover to turn the album art, song name or notch display on or off.
- Hover over the notch to open the mini player. Click the progress bar to seek.
- Quit with the power icon in the popover.

## Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/YOUR-USERNAME/MusicControl.git
   cd MusicControl
   ```
2. Open the `.xcodeproj` file in Xcode.
3. In **Signing & Capabilities**, choose your own Team (a free Apple ID works).
4. Make sure **App Sandbox** is not enabled, and that the Info settings include:
   - `Privacy - AppleEvents Sending Usage Description`
   - `Application is agent (UIElement)` set to `YES`
5. Press **Command+R** to build and run.

## How it works

| File | Purpose |
| --- | --- |
| `MyApp.swift` | App entry point and the menu bar item |
| `PlayerStore.swift` | Reads the current track from Apple Music and sends commands, using AppleScript |
| `ContentView.swift` | The popover UI |
| `Notch.swift` | The notch window, hover detection and notch UI |

The app polls Apple Music about once per second through AppleScript and publishes the result to the SwiftUI views. The notch is a borderless, transparent window placed over the top-centre of the screen, which expands and collapses based on the cursor position.

## Roadmap

- [ ] Spotify support
- [ ] YouTube Music support
- [ ] Launch at login
- [ ] Optional lyrics view
- [ ] Notarized builds

## Contributing

Issues and pull requests are welcome. If you're planning a larger change, open an issue first so we can talk it through.

## License

Add a license of your choice, such as [MIT](https://choosealicense.com/licenses/mit/), by creating a `LICENSE` file in the repo.
