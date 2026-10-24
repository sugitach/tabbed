## Window-switch diagnostics (in progress, 2026-10-23)

An opt-in local trace is being prepared for unexpected resizing, visible inactive windows, stale closed-window tabs, and bottom-right movement. It records IDs, geometry, AX results, and notification ordering without titles, URLs, or page content. This is diagnostic instrumentation, not a verified fix; live Chrome/Incognito testing remains pending. See [recording steps and limitations](docs/window-diagnostics.md).

### windows are better 
# tabbed

https://github.com/user-attachments/assets/8b628294-754c-44bd-9088-425cc25b8098

```sh
brew trust --cask zimengxiong/tools/tabbed
brew tap ZimengXiong/tools
brew install --cask tabbed
xattr -dr com.apple.quarantine /Applications/Tabbed.app
```
on first launch, grant **System Settings -> Privacy & Security -> Accessibility**

hold ⌘ while dragging windows to create tab groups

use kb shortcuts alt+1...n to switch between tabs, and alt+tab to cycle between tabs. configure other bindings in ~/.config/tabbed.toml. a config is created for you on first launch
