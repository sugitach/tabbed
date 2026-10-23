## Chromeタブ移動時の自動追加対策と終了経路（2026-10-23）

自動追加の対象を生成通知のウィンドウ自身に限定し、左ボタン押下中の追加を待つ。復元失敗時は停止状態を明示し、別の確認を経て「復元せず終了」できるようにする。本体の保存先は `fix/restore-windows-on-quit` 起点の `fix/chrome-tab-transfer-and-quit-recovery`、追加テストは前回のテスト枝起点の `test/chrome-tab-transfer-and-quit-recovery`。両枝をdevelopで統合して検証する。実Chromeでの原因確定・解消確認と実ダイアログの表示確認は未完了で、インストール済み版は更新しない。[調査・修正・検証の記録](docs/chrome-tab-transfer.md)。

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
