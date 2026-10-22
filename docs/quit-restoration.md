# 通常終了時のウィンドウ復元修正（2026-10-20）

最新（2026-10-21）: 通常時のpruneが一時AX失敗を閉鎖として窓を落とす経路を非GUIで再現し、isKnownClosedによる整理と停止後guardで修正した。既存7件＋本体処理の11件、全本体の型検査が成功。[実施結果](build-validation.md)と[段階計画](../README.md)を参照。以下の過去の未実施記述は当時の履歴として残す。実AXのエラー再現と実OS終了経路は未検証。

## 作業元と範囲

- 個人 fork: https://github.com/sugitach/tabbed （Webで ZimengXiong/tabbed の fork と確認）
- 独立 clone: `/Users/t-sugita/work/private/tabbed-fork`
- origin: `https://github.com/sugitach/tabbed.git`
- upstream: `https://github.com/ZimengXiong/tabbed.git`
- ブランチ: `fix/restore-windows-on-quit`
- clone 時の HEAD / origin/main: ともに `9481b628767921bd1af1b90c4d7448282c9757b6`。検証済みコミットと完全一致。作業開始時の変更なし。
- 既存 `tabbed-local/upstream`、署名済み成果物、exports、VM は変更していない。グローバル Git 設定・認証も変更なし。
- 未コミット。個人用作者 identity は未確認で、既存の仕事用 identity は採用していない。push、PR、公開なし。

## 手動試験の報告と原因

ユーザーによる隔離 VM の Terminal/Finder 2枚試験では、グループ化、切り替え、リサイズ同期、タブの x による解除が正常。グループ化したまま Quit すると非アクティブ側 Finder が画面外に残り、「すべてのウィンドウを表示」に残るが選択しても戻らないとの報告。ズームによる復旧の成否は未確認。軽微なグループ化直後の位置ずれは対象外。

固定コミットでは GroupOperations の parkOffscreen が非アクティブウィンドウを画面右下へ退避する一方、Quit は NSApplication.terminate を直接呼び、終了前の全グループ復元がない。これは静的確認。今回、修正版の動作確認はしていない。

## 変更

- applicationShouldTerminate で全ウィンドウの復元を試行。成功時だけ通常終了。失敗時はアプリ名・ウィンドウ名を表示し終了を中止する。
- controller は最初に停止フラグを立て、ドラッグ／キー監視、タイマー、Workspace通知、AX監視を停止。パネルを非表示にし、全グループの配列をスナップショット化して復元する。dissolve による走査中のグループ削除はしない。
- 遅延ドラッグ、ウィンドウ自動追加の再試行、Z-order更新、AX同期、パネル操作などの入口は停止後に何もしない。失敗後のモーダル表示中や、その後のイベント処理でも再退避を防ぐ。
- 全ウィンドウを処理し、途中の失敗で後続を打ち切らない。明確に閉じたウィンドウのみスキップ。AXタイムアウト・権限エラーは閉鎖とみなさない。復元途中で閉じたケースも再確認する。
- 共有 frame を現在の画面の visibleFrame 内に収める。別ディスプレイがなくなった場合や大きすぎる frame も補正。各 Space の所属は変えず、raise/activate によるフォーカス奪取はしない。
- AX のサイズ／位置変更の戻り値を確認し、読み戻した frame の各値が目標と2ポイント以内か確認。AX拒否、非同期反映、最小サイズ制限などでは保守的に失敗と扱う。
- 復元失敗後は管理を停止したまま対象を保持し、次の Quit で再試行する。成功済みの対象も再確認する。通常のタブ管理を自動再開する設計ではない。
- applicationWillTerminate も同じ復元処理を呼ぶ。成功済みなら対象は空。強制終了やクラッシュ時の復旧は対象外。

## 確認済み／未実施

実施済み:

- Git の fork main の SHA、リモート設定、開始時のクリーン状態を確認。
- `git diff --check` 成功。
- SDK26.5 を指定した `swiftc -frontend -parse` で全 Sources と Tests の構文解析成功。オブジェクト・アプリを生成せず、型チェック／リンク／アプリ起動も行っていない。
- Sources 内の async / asyncAfter / Timer と終了通知の経路を静的レビュー。
- WindowRestorationTests を7件追加：複数グループと途中失敗、途中閉鎖、画面なし、画面外・過大サイズ、負座標ディスプレイ、不正frame、再試行。これらは復元ポリシーを検証するテストで、AXや終了ライフサイクルの統合試験ではない。

未実施:

- 型チェック、ビルド、XCTest実行、生成アプリ起動、署名、媒体生成、VM試験、インストール、権限変更。
- 実際の停止順序・遅延callback抑止・NSApplication終了経路・AX失敗表示の動作確認。
- 本環境は `xcode-select -p` が CommandLineTools、`xcodegen` は PATH 上になく、既存 project.yml を使う XCTest には追加の開発環境が必要。

初回 `git ls-remote` は DNS 解決失敗。ネットワーク接続可能な実行環境での明示的な git clone は承認され成功した。拒否された操作はない。結果不明・承認待ちの操作もない。

## 今後のビルド・テスト案（今回未実行）

完全な Xcode と XcodeGen が利用可能な環境で、別途ビルド／テストの実行範囲を確認してから、clone 内で以下を行う。インストールやグローバル設定変更はこのコマンドには含まない。

```sh
xcodegen generate --spec project.yml
xcodebuild -project Tabbed.xcodeproj -scheme Tabbed \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-quit-fix \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project Tabbed.xcodeproj -scheme Tabbed \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-quit-fix \
  CODE_SIGNING_ALLOWED=NO test-without-building
```

生成された scheme に TabbedTests が含まれることを実行前に確認する。既存の test host は XCTestConfigurationFilePath がある場合 applicationDidFinishLaunching から早期 return するが、test-without-building はアプリをテストホストとして実行する。このため今回の静的確認の範囲では実行していない。ビルドには project.yml の作者用署名設定を使わず CODE_SIGNING_ALLOWED=NO を指定。VM配布用コピーへのad-hoc署名と媒体作成は別工程。

## 次の隔離 VM 手動試験案

1. 復元用 clean VM と旧成果物を保全し、新ビルドは別名の媒体で試験VMに渡す。ネットワーク・共有は無効のまま。ビルド識別とSHA、署名を先に確認する。
2. Terminal/Finder をグループ化し、片方が非アクティブのまま通常 Quit。両ウィンドウが画面内に戻り、選択でき、しばらく待っても再退避しないことを確認。
3. 3枚以上／複数グループでも全対象を確認。各グループの共通位置へ戻るためウィンドウ同士の重なりはあり得る。重なりと画面外退避を区別する。
4. Quit直前に元アプリ側で1枚を閉じる、ウィンドウ新規作成直後に Quit、移動・リサイズ直後に Quit を試す。異なるSpaceも必要に応じて確認する。
5. 復元失敗はまず fake ベースのテストで確認。実際のAX拒否・タイムアウト・終了中止表示と再試行は未検証として残し、追加の権限変更を伴う試験は今回の承認に含めない。
6. タブの x による通常解除が従来どおり動くことを確認する。グループ化直後の位置ずれは引き続き対象外。
