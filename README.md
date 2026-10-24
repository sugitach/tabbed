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

Mouse and modifier activity in other applications is observed using asynchronous
`NSEvent` copies. Tabbed does not install a `CGEventTap`, change or suppress raw
input, or generate replacement input. Tab-strip clicks use normal AppKit/SwiftUI
event delivery. Accessibility permission is still needed to manage other apps'
windows. These changes do not by themselves establish that permission changes
while running are safe on every macOS version.

At startup, if no mouse event has been observed, the passive observer is
reinstalled at most twice while no mouse button is held. This does not require
opening the menu or enabling diagnostics. Enabling diagnostics records the
current observer state without starting or reinstalling it.
