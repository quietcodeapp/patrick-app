<p align="center">
  <img src="AppIcon.png" width="128" alt="Patrick app icon">
</p>

# Patrick: The Star for Safari Bookmark

Safari extensions for macOS that add a <b>pink star</b> for bookmarks and a <b>yellow book</b> for the Reading List.

[Realease](https://github.com/quietcodeapp/patrick-app/releases) | Developed by [QuietCode](https://quietcode.app)

![](screenshot1.png)

![](screenshot2.png)

## Download

Get the latest `Patrick-x.y.dmg` from the [Releases](../../releases/latest) page. It is signed and notarized.

1. Open the DMG and drag **Patrick** to Applications.
2. Open Patrick and turn on **Full Disk Access** for it in System Settings → Privacy & Security.
3. In Patrick, click **Connect Safari**.
4. In Safari → Settings → Extensions, enable both Patrick extensions.

You can quit Patrick after connecting. Adding and removing happens inside the extensions.

## How it works

Safari has no public API for adding bookmarks, so Patrick merges bookmark/reading list into and out of `~/Library/Safari/Bookmarks.plist` (hence Full Disk Access).

## Known limitations

- Safari's sidebar or Favorites UI may not refresh immediately.

## License

[GPL-3.0](LICENSE)
