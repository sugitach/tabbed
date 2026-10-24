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

Shortcuts are registered with macOS while Tabbed's window management is running,
and unregistered when it stops or the configuration is reloaded. They act only
when the focused window belongs to a tab group; in other windows the registered
chord does nothing and is not delivered to the application. Enabled system
shortcuts and conflicting global registrations are skipped. Registration issues
appear in the menu bar menu (hover for details); change the modifier in
Configuration and reload to retry. Application-specific menu shortcuts cannot
all be detected in advance; choose chords that do not overlap those you use.
