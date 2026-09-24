# Patrick - The Bookmark Star for Safari

Safari extensions for macOS that add a **pink star** for bookmarks and a **yellow book** for the Reading List.

![](screenshot1.png)

![](screenshot2.png)

## Download

Get the latest `Patrick-x.y.dmg` from the [Releases](../../releases/latest) page. It is signed and notarized.

1. Open the DMG and drag **Patrick** to Applications.
2. Open Patrick and turn on **Full Disk Access** for it in System Settings → Privacy & Security.
3. In Patrick, click **Connect Safari**.
4. In Safari → Settings → Extensions, enable both Patrick extensions.

You can quit Patrick after connecting. Adding and removing happens inside the extensions.

## What it does


|                                    | Star (Bookmark)                   | Book (Reading List) |
| ---------------------------------- | --------------------------------- | ------------------- |
| Shows if the current page is saved | Yes (filled icon)                 | Yes                 |
| Add                                | Pick a folder in the popup → Add | Click to toggle     |
| Remove                             | Popup → Remove                   | Click to toggle     |
| Move to another folder             | Popup dropdown (when saved)       | —                  |
| Filled icon color                  | `#e67e7c`                         | `#f0d04e`           |

## How it works

Safari has no public API for adding bookmarks, so Patrick merges leaf entries into and out of `~/Library/Safari/Bookmarks.plist` (hence Full Disk Access).

## Known limitations

- Safari's sidebar or Favorites UI may not refresh immediately; restarting Safari fixes it.


## License

[GPL-3.0](LICENSE)
