# 修正版のビルド・転送媒体検証（2026-10-20）

ユーザーの継続承認に基づき実施。`fix/restore-windows-on-quit` の未コミット差分を使用。親コミットは `9481b628767921bd1af1b90c4d7448282c9757b6`。今回ソースの追加修正は不要だった。旧ビルド・媒体・VM は変更していない。

## 結果

出力ルート: `/Users/t-sugita/work/private/tabbed-quit-validation/20261020T113441Z`

- SDK `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` を明示。
- 全アプリソースの `swiftc -typecheck` 成功、診断なし。
- arm64 / minimum macOS 14.0 / SDK 26.5、最適化ビルド成功、診断なし。Mach-O load commands でも確認。
- 非GUIテスト7件すべて成功。CLTには XCTest framework がないため、WindowRestorationTests の本文から XCTest import と @testable import を外し、XCTAssert 相当を precondition に置き換えて、実際の WindowRestoration.swift と一緒に独立した実行体にコンパイルした。7メソッドを明示的に呼んだ。アプリ本体・AppDelegate・AX・パネルをリンクしていない。**XCTestランナーによる試験ではなく、終了ライフサイクルや実AXの統合試験でもない。** 入力と生成ハーネス、コンパイル・実行ログを保存。
- ビルドした app の別コピーに ad-hoc / hardened runtime 署名。`codesign --verify --strict --verbose=2` 成功。
- 署名済み app を `ditto -c -k --sequesterRsrc --keepParent` で ZIP 化し、HFS+ / ISO9660 raw 媒体へ格納。
- 実際の ISO を標準 tar で読み、ZIP・マニフェスト・手順書のバイト一致を確認。取り出した ZIP を ditto 展開し、全 app パス・全ファイル内容・POSIX モード一致、署名再検証成功。展開後の属性は com.apple.provenance のみで、FinderInfo はなかった。
- 全ソースのビルド前後 SHA 一致、`git diff --check` 成功。

## 成果物と SHA-256

| 対象 | パス（出力ルートから） | SHA-256 |
| --- | --- | --- |
| 媒体（モード0444） | `Tabbed-Quit-Fix.iso` | `4b62f098ec854bd739b211102ef676f577031f375cdddab2bd0d6ff1a6560cc6` |
| ZIP | `payload/TABBED.ZIP` | `8ead3f3d6d01b5b4ae903283825a6921b0b76afa51573371002ff50f1f1b0c26` |
| 署名後実行ファイル | `signed/Tabbed Quit Fix.app/Contents/MacOS/Tabbed` | `e243618224ad8ecb90437de4848e596b571a31d5e4d6cc40ffba9a989e2cf073` |

bundle 全ファイルのハッシュは媒体内 `BUNDLE.SHA`。署名前アプリは `build/`、署名後コピーは `signed/`、媒体から取り出した検証コピーは `roundtrip/extracted/`。

## 再現と証跡

出力ルートの `validate.py`、`test-policy.py`、`package.py` は実行したレシピの保存コピー。実行時は一段上の `/Users/t-sugita/work/private/tabbed-quit-validation/` に置いて順に `python3 validate.py`、`python3 test-policy.py`、`python3 package.py` を実行した。validate.py は UTC 時刻の新規出力を作り、latest-path.txt を後続へ渡す。保存コピーは単なる証跡で、既存出力上で再実行しない。

- `*-command.json` / `packaging-commands.json`: 実引数。
- `typecheck.log` / `build.log`: コンパイラ診断（空、exit 0）。
- `policy-tests-build.log` / `policy-tests-run.log`: 独立テストのビルドと7件成功。
- `signature.log` / `verify.log` / `roundtrip-verify.log`: 署名と再検証。
- `load-commands.txt`: SDK / minimum OS。
- `source-sha256.json` / `source.patch` / `source-snapshot.tar.gz`: 実ソースのハッシュ、追跡済み差分、未追跡追加ソースも含むスナップショット。
- `roundtrip-result.txt` / `media-sha256.txt`: 媒体の検証。

## ゲストでの最小手順

1. 試験 VM を停止して、新しい ISO を Removable / Read Only の媒体として選択する。clean 複製は保全し、ネットワーク・フォルダ共有・クリップボード共有を無効のまま維持。
2. ゲスト起動後に Terminal で、実際にマウントされた媒体のディレクトリへ移動する。`/Volumes/Tabbed-Quit-Fix` がその名前で存在する場合の例:

```sh
cd /Volumes/Tabbed-Quit-Fix
shasum -a 256 -c SHA256SUMS
mkdir "$HOME/Tabbed-Quit-Fix-Test"
ditto -x -k TABBED.ZIP "$HOME/Tabbed-Quit-Fix-Test"
cp BUNDLE.SHA "$HOME/Tabbed-Quit-Fix-Test/"
cd "$HOME/Tabbed-Quit-Fix-Test"
shasum -a 256 -c BUNDLE.SHA
codesign --verify --strict --verbose=2 "Tabbed Quit Fix.app"
```

各行の成功を確認してから次へ進む。展開先が存在するときは上書きせず別の新規名を選ぶ。署名検証前に Finder で app 内を開かない。ZIP内の署名済み bundle は媒体を Finder で見るだけでは変更されない。ゲストでの展開後の属性付加を完全に防ぐ保証ではないため、失敗時は停止し `xattr -lr "Tabbed Quit Fix.app"` 等で原因を記録する。属性の一括除去や再署名はしない。

3. 全ハッシュ・署名が合格してからユーザーが修正版を試験起動する。既存のゲストAX許可が新ビルドに通用するかは未確認。追加権限要求が出たら自動で進めず状況を確認する。
4. Terminal/Finder 2枚をグループ化したまま通常 Quit。両方が画面内へ戻り、選択でき、待っても再退避しないことを確認。続いて複数グループ、Quit直前のウィンドウ閉鎖・移動・新規作成を試す。詳細は quit-restoration.md を参照。

## 未実施と操作状態

ホストでの Tabbed 起動・インストール、VM/CUA操作、権限・認証・システム設定変更なし。XCTestランナー、実AX、終了通知・失敗ダイアログの統合試験は未実施。媒体マウントとゲストの展開・Quit 動作は未検証。未コミット・未push。

今回の型チェック、ビルド、独立テスト、署名、媒体作成、往復検証はすべて成功。拒否・承認待ち・結果不明の操作はない。


## 手動VM再試験の追記（2026-10-21、日本時間）

以下はユーザーからの報告。エージェントによるGUI操作・再現試験ではない。

- ゲストのアクセシビリティ一覧では初めからオンだったが、起動時の確認が繰り返された。オフ／オンでは解消せず、ユーザーが一覧から削除してアプリ再起動後に登録し直すと通るようになったとの報告。原因をTCC内部の不整合と断定するためのログは取得していない。
- ドラッグ時の枠が出ない件は、⌘キーを押さずに操作していたため。⌘ドラッグでグループ化できたとの報告で、修正版の回帰とは扱わない。
- FinderとTerminalの2枚をグループ化したままQuitすると、同じ位置に両ウィンドウが重なった状態で終了した。画面外へ残る現象はこの試験では報告されなかった。Quitで共通位置へ戻す実装と一致する。タブのxによる解除時の位置ずらしは今回の変更に含めていない。
- 続いて2組のグループでも「大丈夫」と報告あり。通常Quitによる複数グループ復元も手動試験で確認済み。

上記範囲で今回の不具合の再試験は成功。前節の「ゲストQuit動作は未検証」は媒体作成時点の履歴として読む。ゲスト内ハッシュ・署名の具体的な照合出力、Quit直前の閉鎖・移動・新規作成、復元失敗時の表示と再試行、別Space／複数ディスプレイは、この追記では確認済みにしていない。ホストへのインストールや公開の可否を判断する包括的な安全性確認ではない。

## 段階1: 一時AXエラーとQuit復元の内部回帰（2026-10-21）

見直した段階計画に従い、`bash Tests/test.sh` を非GUI内部回帰の既定入口にした。Xcode/XCTest環境は追加していない。実際の本体からisKnownClosed/isAlive、pruneDeadWindows、remove/dissolve/untab、restoreWindowsForTermination、停止後callbackのメソッド本体を取り出し、内容を変更せずコンパイルする。@objc宣言属性だけをテスト用に除外する。生成されたProductionMethods.swiftと元ソースのsnapshot/hashを保存する。

AX関数・プロセス一覧・画面・パネル・監視・レイアウト副作用はテストダブル。特にrestoreFrameの実AX書き込み、AppDelegate/NSApplication、実OS通知や入力配送は実行していない。ソースの選択メソッドと実際のWindowRestoration.swiftを検証しており、UI境界の統合試験と混同しない。

修正前結果は `Tests/Regression/results/20261021T035536552135Z/`。コンパイル成功、既存7件成功、新11件中3件失敗。一時cannotComplete、権限等のエラー、停止後の直接pruneで復元対象が失われる再現が得られた。テスト準備時の抽出・テストダブルの型検査失敗ログも別出力に保全している。

本体修正はWorkspaceのpruneへ `guard !isStopping` を追加し、削除条件を `!engine.isAlive` から `engine.isKnownClosed` に変更しただけ。既存の閉鎖判定と復元処理を再利用し、タイムアウト/権限等の未知状態は対象に保持する。明確な閉鎖は従来どおり整理する。WindowEngineのコメントも閉鎖と不明の区別を明記した。

修正後結果は `Tests/Regression/results/20261021T035643053105Z/`。既存7件＋新11件すべて成功し、SDK26.5/arm64で全本体の型検査も成功。snapshotは実行中に変化していない。確認内容は次のとおり。

- 一時失敗から回復後、元の全窓へQuit復元を試みる。
- エラー/不明を閉鎖と扱わず、invalidUIElement・ID変化・プロセス終了/不在だけを整理する。
- 複数グループの途中失敗でも後続を処理し、失敗時は対象を保持したまま停止し、再度Quitで再試行できる。
- 復元中の実際の閉鎖、停止順序、遅延callbackによる再整理/再配置の抑止、成功後の二重終了を模擬境界で確認する。
- xによる解除は32ポイントの既存offsetを保ち、単一窓になったグループのdissolveも生存窓を戻す。

結果・コンパイルコマンド・抽出したソース・ハッシュは同ディレクトリ。resultsはgit除外し、テスト実装だけを管理する。`project.yml` は `Tests/Regression/**` を既存XCTestから除外し、テストダブル/main.swiftをアプリ付きXCTestへ混入させない。既存の3つのXCTestファイルは変更していない。

今回の新しいprune修正は非GUIで検証したソースのみで、既存の署名済みTabbed実行ファイルへは反映していない。段階3で修正版アプリを実証する際は新しいbuild/hashを確認する必要がある。ホストのアプリ起動・VM操作・権限変更・commit/pushは行っていない。


## ブランチ分割とコミット前の非GUI再検証（2026-10-22）

**通常Quit修正、一時AXエラー対策、テスト追加を別ブランチへ分割した。VM試験は再開していない。** 元の未コミット差分と未追跡ソース/文書をローカル退避してから、実ソースを変更せずGitのステージ内容を分割した。

| ブランチ | 親 | コミット/内容 |
| --- | --- | --- |
| `fix/restore-windows-on-quit` | `9481b628767921bd1af1b90c4d7448282c9757b6` | `e269d6426f94b67e5d11bed74731e7116e5dcd8c` — 終了時復元と停止処理、isKnownClosed契約 |
| `fix/retain-windows-on-ax-errors` | 上のQuit修正 | `08e12aa76d90c92a379a8f8fd81779b0ccba72c2` — pruneを既知閉鎖に限定、停止後guard |
| `test/window-restoration-and-guest-e2e` | 上のAX修正 | Tests/Regression、WindowRestorationTests、guest-e2e、入口/除外設定/手順/実測記録 |

2件目の修正は1件目のisKnownClosedを再利用し、テストは両修正に依存する。3ブランチはこの順で積んだもので、mainから独立した3つの差分ではない。main/origin/mainは元コミットのまま。既存tools/guest-e2eはTests/guest-e2eへの相対symlinkとして互換案内を保持する。commitの作者はユーザー指定の `SUGITA, Toshinori <t-sugita@riraku.com>` を個別コマンドに指定し、global/localのGit作者設定は変更しない。push/PR作成なし。

分割時の確認:

- `bash Tests/test.sh internal` 成功。既存復元ポリシー7件と本体から抽出した処理の11件、全18件。本体のSDK26.5/arm64型検査も成功。証拠はGit除外のローカル `Tests/Regression/results/20261022T004031704100Z/`。実AX/UI境界は模擬でありXCTestランナー/実OS試験ではない。
- Quit修正だけのステージ済みソースを別ディレクトリへ取り出し、全本体の型検査成功。AXのprune修正を未適用でも型が成立することを確認。
- 現guestソースのSharedのみと、保全済み最終0.11 source snapshot内の生成PinnedTarget.swiftを使い、純粋判定176件成功。AppKit/AX/CGEventを含むアプリは実行せず、既存バイナリ/媒体を再ビルドしていない。
- 媒体ポリシー25件成功。入口/媒体スクリプトのbash構文、3つのPythonスクリプトの構文確認成功。
- Gitへの追加対象はソース・スクリプト・文書・symlinkのみ。ISO/app/VM/実行ログ/compiler cacheは含めない。実行可能ファイルを除外したという意味ではなく、shell/Pythonソースの既存modeは保持する。

最新0.11の解除/regroup/通常Quit復元は未検証のまま。過去の手動Quit成功報告は上の履歴どおりで、今回新たにGUIで再確認したものではない。ホスト/guestの権限、隔離設定、未保存文書、既存成果物は変更しない。


## main起点への再構成（2026-10-22）

上の積み上げ構成は履歴として残し、現ブランチはすべてmainから直接分岐する形へ変更する。Quit側とAX側には同一のisKnownClosed契約/実装を含め、停止後のprune guardはQuit側に置く。これにより各バグ修正を単独で型検査でき、統合後の本体ソースは以前の完成形と同じになる。

テストブランチは本体Sourcesを変更しない。任意の終了コールバックがないmainでもビルドを成立させ、通常Quit後に元の窓が復元されない結果で失敗を示す。テストダブルが欠けた復元処理を実装することはない。旧7件のポリシー単体テストは通常Quit経由の7ケースへ組み替え、既存11件と合わせた18ケースを同じCLT入口で実行する。XCTestには同CLIを起動して終了コードを検査する薄いアダプターを置く。Xcode/XCTest本体は未実行のまま。

旧3コミットは `archive/stacked-20261022-quit` / `archive/stacked-20261022-ax` / `archive/stacked-20261022-tests` のローカル保全タグで参照できる。mainとoriginは変更せず、developをmainから作って3ブランチを個別にマージする。新GUI操作・build/sign/package・guest再実行・権限変更・pushは行わない。以下へ各構成の非GUI検証結果を追記する。


### 修正前と各修正単独の結果

同じ18ケースを各構成に適用した。すべてテスト実行体のコンパイル、本体型検査、XCTestアダプターの宣言shimによる型検査は成功し、失敗はテストの実行結果として返った。実NSApplication/AXは実行していない。

| 本体構成 | コンパイル/本体型検査 | 内部回帰 | 解釈 |
| --- | --- | --- | --- |
| main + テストのみ | 成功 | 2/18成功、16失敗 | Quit復元と一時AX保持の不具合を検出 |
| Quit修正のみ + 同じテスト | 成功 | 15/18成功、3失敗 | Quit要件は通過し、一時AX保持の3ケースが失敗 |
| AX修正のみ + 同じテスト | 成功 | 4/18成功、14失敗 | 不明AXの保持/閉鎖分類は通過し、Quitを要するケースは失敗 |

main+テストの結果はローカル `Tests/Regression/results/20261022T005930443911Z/`。単独修正の証拠は `/tmp/tabbed-independent-branches-gyauaeki/quit-only/Tests/Regression/results/20261022T010006138294Z/` と同 `ax-only/Tests/Regression/results/20261022T010006138059Z/`。過去の7+11件の数は当時の実測であり、現在は通常Quit経由の18ケースである。XCTestアダプターはCLIを実行するため、修正前はコンパイルできてもassertionが失敗する。

共通APIを両修正に含めたため、AXWindowEngine/WindowEngineの同じ挿入位置でGitの自動マージが競合する。統合時は同じisKnownClosedを1つだけ残し、Quit固有のrestoreFrameも保持する。AX修正がQuit側の実装やコミットを必要とする依存ではなく、同一追加を2回含めたことによるテキスト競合である。統合後のSources全ファイルを保全した以前の完成形とSHA256で照合する。
