## Chromeタブ移動時の自動追加対策と終了経路（2026-10-23）

自動追加の対象を生成通知のウィンドウ自身に限定し、左ボタン押下中の追加を待つ。復元失敗時は停止状態を明示し、別の確認を経て「復元せず終了」できるようにする。本体は `fix/restore-windows-on-quit` 起点の `fix/chrome-tab-transfer-and-quit-recovery`、追加テストは前回のテスト枝起点の `test/chrome-tab-transfer-and-quit-recovery` に分離し、developへ統合済み。統合後の非GUI回帰33/33・本体型検査が成功した。実Chromeでの原因確定・解消確認と実ダイアログの表示確認は未完了で、インストール済み版は更新しない。[調査・修正・検証の記録](docs/chrome-tab-transfer.md)。以下は以前の保存状態と履歴。

## Chromeタブ移動と復元失敗後の終了経路の回帰（2026-10-23）

前回の `test/window-restoration-and-guest-e2e` 起点の `test/chrome-tab-transfer-and-quit-recovery` で、内部回帰を18件から33件へ拡張する。本体修正は `fix/restore-windows-on-quit` 起点の `fix/chrome-tab-transfer-and-quit-recovery` に分離する。このテスト枝はSourcesを変更しないため、単独では未修正の振る舞いを失敗として検出する。両枝をdevelopへ統合して全33件の成功を確認する。実Chrome・ダイアログのE2E成功とは扱わず、VM試験やインストール更新は行わない。

テスト枝単独での検証：テスト実行体のコンパイル・本体全体の型検査・XCTestアダプターの宣言shim型検査が成功。回帰は4/33成功で、未取り込みの本体修正を29件の失敗として検出した。ローカル証拠は `Tests/Regression/results/20261023T023412627848Z/`。この結果は統合したdevelopの結果とは区別する。

## 保存状態: main起点の3ブランチとdevelop（2026-10-22）

バグ修正2本とテスト追加は、すべて未変更のmainから直接分岐する構成に作り直した。developもmainから作り、この3本を個別にマージ済み。旧積み上げコミットはローカルの `archive/stacked-20261022-*` タグに保全。push/PRは行わない。

| mainから直接分岐するブランチ | 内容 |
| --- | --- |
| `fix/restore-windows-on-quit` | 通常Quit前の全窓復元、停止処理、失敗時の終了中止と再試行 |
| `fix/retain-windows-on-ax-errors` | 一時AXエラーを閉鎖と扱わず、管理対象を保持 |
| `test/window-restoration-and-guest-e2e` | 修正前でもコンパイルできる内部回帰、guest harness、スクリプトと記録 |

検証結果: main＋テストはコンパイル/本体型検査に成功し、回帰は2/18成功（16件の不具合検出）。developでは同じ18件すべて成功した。Quit単独15/18、AX単独4/18も確認した。フルXcode/XCTestとVM試験は再開していない。

両バグ修正に共通のisKnownClosed契約/実装は同じ内容を含める。停止後のprune抑止はQuit側に置き、AX修正をisStoppingへ依存させない。テスト側は本体Sourcesを変更せず、通常終了の任意コールバックがない場合もコンパイルし、未復元の窓を振る舞いの失敗として判定する。新しい型/メソッドの偽実装で修正前を成功させない。

**VM試験は終了のまま。** 最新0.11の本体E2Eはgroup後の押下状態検査で停止し、解除/regroup/通常Quit復元は未検証。今回の整理でアプリ/VM起動や入力/権限変更を再開しない。既存成果物・生ログ・VMはGit除外でローカル保持。[現在の検証方式](Tests/guest-e2e/README.md#main起点のテストと非gui回帰) / [再構成記録](docs/build-validation.md)。以下は履歴。

## 履歴: 最初の積み上げ型ブランチ分割（2026-10-22）

本体修正とテスト実装を次の3ブランチに分けた。`main` は変更せず、push/PRは行わない。2件目は1件目で追加した閉鎖判定を使い、テストは両修正を対象とするため、ブランチを順に積んでいる。

| ブランチ | 直前のブランチから追加する内容 |
| --- | --- |
| `fix/restore-windows-on-quit` | 通常Quit前の全窓復元、監視/遅延処理停止、復元失敗時の終了中止と再試行 |
| `fix/retain-windows-on-ax-errors` | 一時AXエラーを閉鎖と扱わず管理対象を保持、停止後のprune抑止 |
| `test/window-restoration-and-guest-e2e` | 復元のXCTestソース、CLT用内部回帰、隔離guest harness/fixture、スクリプトと実施記録 |

今回の分割時に内部回帰18件、本体の型検査、Quit修正単独の型検査、guest純粋判定176件、媒体ポリシー25件、shell/Python構文を確認した。GUIアプリ/VMは起動していない。既存ISO・署名済みapp・ログ・VMはGitに含めず、ローカルに保持する。

**guest E2Eは未完了のまま作業終了。** 最新0.11はgroup操作後の押下状態検査で停止し、解除/regroup/通常Quit復元は未検証。以前のユーザー手動Quit試験と最新自動試験は別の結果である。実装・署名の完成を全試験PASSと扱わない。[分割と再検証](docs/build-validation.md#ブランチ分割とコミット前の非gui再検証2026-10-22) / [guest試験の記録](Tests/guest-e2e/docs/build-result-20261021.md)。以下は過去の履歴。

## 履歴: 0.11はgroup操作後の入力解放検査で停止

承認後にguestのauto-addをOFFにし、同じ0.11を新runで1回実行した。専用2窓のスタックは画面に現れたが、直後のOS押下状態検査が失敗した。送信auditのmouseUp/Command解放とFixtureのCommand解放受信は確認済み。グループ状態の自動検証・解除・再グループ化・Quit復元は未完了。最初の失敗で止め、3appと全ログを保全した。追加権限・build・再試行なし。[実測と残存状態](Tests/guest-e2e/docs/build-result-20261021.md#011-auto-add-off後の再実行group後の解放状態検査で停止)。以下は過去の履歴。

## 履歴: 0.11導入後の初回E2Eは入力前に停止

同一0.11をguestへ検証導入し、同Harness/TabbedだけのAX登録を更新した。E2E起動は1回。Tabbedのauto-add保存設定がONのためpreflightで停止し、Fixture/本体起動・入力・グループ化以降は未実施。設定変更や再実行はしていない。停止画面とログ、未保存TextEdit、隔離を保持。[実測結果](Tests/guest-e2e/docs/build-result-20261021.md#011-guest導入許可更新と初回preflight停止)。以下の承認待ちや未導入は準備時点の履歴。

## 段階3: 0.11媒体完成・guest実行承認待ち

グループ化→⌘ドラッグで引き出して解除→再グループ化→通常Quit復元を、専用Fixture2枚と単独 `run e2e` で確認する0.11を準備した。本体ソースは変更せず最新修正を含めてbuildし、その署名済みhashをHarnessへ固定した。176 pure assertions・媒体25ケース・3アプリの型検査/build/署名・実ISO往復に成功。guestへの導入・起動・許可更新は未実施。[実行対象・手順と制約](Tests/guest-e2e/README.md)。x解除とAX障害注入は今回の対象外。以下は過去の準備・実測記録。

## 段階3: 本体E2Eの試験順を準備（未実行）

2枚でグループ化→解除→再グループ化→通常Quitを確認する仕様を[テストREADME](Tests/guest-e2e/README.md)に整理した。既存0.10のE2Eには解除・script入口がなく、古い入力guardと旧Tabbed hashも残るため、そのままは実行しない。署名/hash・静的確認まで完了、新版作成/guest実行/権限変更は今回行っていない。

## 現在: 0.10の⌘クリック・⌘ドラッグが各1回成功

ユーザー本人の直接の実行承認後、導入済み0.10で⌘クリック1回、成功確認後に⌘ドラッグ1回を実行し、両方PASS。専用Fixtureの受信列、raw flags、座標、mouseUpと⌘解放を確認した。Harness/Fixtureは正常終了済み。Tabbed本体のグループ化・解除・Quit復元の自動E2Eは未実施。[実測記録](Tests/guest-e2e/docs/build-result-20261021.md#追記-010のcommand-clickとcommand-drag成功)。以下の承認待ち・未実行は過去の記録。

## 現在: 0.10導入済み、Command試験は実行前の審査で停止

0.10のguest導入・素材/署名検証・同Harness許可再登録は完了。Command-click起動操作が「ユーザー本人の直接確認が見えない」と自動審査で拒否され、コマンド未入力・試験未実行のまま停止した。再試行なし。[詳細](Tests/guest-e2e/README.md)。

## 次の段階: Command操作の0.10媒体完成・実行承認待ち

通常click成功後の段階2として、Command操作もsession配送で確認する0.10媒体を作成。ホストの純粋143 assertions・媒体25ケース・型検査/build/署名/ISO往復が成功。押下/待機/マウス操作/解放の順序、raw flags・座標・受信記録を検証し、最初の失敗で停止する。新成果物のguest実行と必要な同Harness許可再登録は具体的確認を受けてから行う。現在はguest未実行。[手順と成功条件](Tests/guest-e2e/README.md)。

# VM入力確認（0.9の通常クリック成功）

ユーザーの直接の実行承認後、0.9のsession通常clickを1回実行しPASS。run `099BBB80-EA09-42B3-A335-FE9E0F45B75D` で専用Fixture Aのtag付きdown/up、Command=false、blankHit=true、受信ログ2件の保存完了を確認した。専用アプリは正常終了済み。⌘操作とTabbed本体E2Eは未実施。[最新結果](Tests/guest-e2e/README.md)。以下の実行前停止は履歴。

0.9はTabbed-Testへハッシュ/署名検証して導入し、同Harnessのguest許可を再登録した。実行コマンドは自動承認審査が実行時点の新しい確認不足として拒否したため、通常clickは未送信。経路を変えて再試行していない。[停止状態](Tests/guest-e2e/README.md)。

具体的な再確認を上位タスクから受けた後も、同じ1回の起動コマンドは「直接信頼できるユーザー確認が見えない」として再度拒否された。再拒否後の画面でもコマンド未入力・アプリ未起動を確認。これ以上の再試行は行っていない。

通常clickだけをsession配送で1回確認する最小変更と署名媒体を準備した。ホストの純粋111 assertions・媒体25ケース・型検査/build/署名・ISO往復は成功、guest未実行。送信前の同一FixtureへのAX hit確認と受信gateを維持し、⌘操作とTabbed本体は対象外。ホストでは非GUI検証と署名媒体作成まで。guest実行/必要な同Harness権限再登録は完成成果物を示して確認する。[現在の手順と履歴](Tests/guest-e2e/README.md)。

## ローカル検証の進め方

目的はグループ化・解除・通常Quitで元のウィンドウが失われず復帰すること。単独の `bash Tests/test.sh` を入口に、次の順に確認する。

| 段階 | 合格条件 | 停止・切替条件 |
| --- | --- | --- |
| 1. 非GUIの内部回帰 | 一時AXエラー後も管理対象を保持。明確な閉鎖だけ除外。複数グループの全窓へQuit復元を試み、失敗時に保持・再試行できる。解除と停止後のcallbackも確認。 | 失敗は本体の最小修正と同じ回帰テストで解消する。Xcode/XCTest環境構築は後回し。 |
| 2. VMの最小入力 | 自前Fixtureへの単純入力、⌘クリック、⌘ドラッグを個別に送り、正しい窓の受信記録・修飾状態・入力解放で判定する。 | 既知の同じ停止原因が続いたら閾値の微調整を繰り返さず、前提と手動入力など代替を見直す。矩形の完全一致そのものを合格目標にしない。 |
| 3. 実OSでの一連操作 | 入力受信確認後、Tabbedのグループ化・解除・通常Quit、元の窓の生存と画面内復帰を確認。 | 内部成功を実操作成功と扱わない。ログを残し、本体の失敗と操作手段の失敗を分ける。 |

段階1は既存の復元ポリシー7件＋実際の本体メソッドを模擬AX/UI境界で検証する11件と全本体の型検査が成功。一時AXエラーでpruneが窓を落とす3件の失敗を修正前に再現し、整理時にisKnownClosedを使う最小修正と停止後のguardで回帰を解消した。これは実AX・NSApplication終了の動作確認ではない。

段階2は承認済み0.4をguestへ導入・検証し、Harnessのguest権限を再登録した。初回plain-clickは前面ウィンドウ判定で入力生成前に停止し、受信は未確認。最初の失敗で止める条件に従い、⌘クリック・⌘ドラッグは未実行、修正や再試行も行っていない。[成果物・ハッシュと実測結果](Tests/guest-e2e/docs/build-result-20261021.md)を参照。HarnessとFixtureは通常終了し、ログ・未保存文書・隔離設定を保全した。commit/pushは行わない。

0.5の `diagnose-point` は対象限定承認後、既存権限のままguestで1回実行した。予定点(210,618)では、CG一覧のindex6のDock（PID1744/window267、layer20、全画面bounds）がFixture A（index8、PID2871/window365）より先に採用され、0.4と同じ拒否条件を再現した。AX hitはAX_NOT_TRUSTED_NO_REQUESTで未取得。入力は送っていない。矩形の重なりを実際の入力先とみなす前提に問題があることは分かったが、Dockの実際のhit挙動は未確認。権限変更・判定の緩和・通常入力の再試行は行わず、専用アプリを正常終了した。[診断結果と制約](Tests/guest-e2e/README.md)を参照。

0.6ではPID宛てprobeだけを修正し、全画面のCG重なりを送信条件にせず、Fixture自身が受信時にtag・Aの窓・実content座標・空白viewのhitを検査してから標準処理へ渡す。Dock/layerの除外は追加せず、session/E2Eのhit判定は維持した。非GUIの98 assertions、型検査・ビルド・署名・ISO往復検証が成功。対象限定承認後にguestへ導入・署名検証し、初回plain-clickを起動したがevent-post preflightで停止した。Fixture起動・入力送信には進まず、残る2probeは未実行。権限を変えず再試行もしていない。[最終媒体・ハッシュ・停止結果](Tests/guest-e2e/docs/build-result-20261021.md)を参照。

その後、同じ0.6のguest権限再登録と入力試験再開への個別承認を受け、正規設定UIでHarnessだけを再登録した。preflightは通過し通常クリックを1回PID宛てに送信したが、input.jsonが存在せず停止。受信成功は未確認で、⌘クリック/ドラッグ、再送、新修正は行っていない。FixtureとHarnessは正常終了し、旧ログ・未保存文書・隔離設定を保持した。

切り分けの対照試験では、同一0.6の入力なし診断で表示した青いFixtureへCUAのclickを1回行い、NSWindow handlerとinput.json出力への到達を確認した。実記録はtag0・Command=falseのdown→drag→up。合成入力の成功ではなく、FixtureはprocessProbe=falseなのでprocess専用受信gateも未検証。診断時のAX hitはFixture Aを示した。専用アプリは正常終了済み。[対照試験の記録](Tests/guest-e2e/docs/build-result-20261021.md)を参照。

0.7はprocess専用modeの通常クリック1回に観測だけを追加し、型検査/build/純粋テスト/署名/媒体往復が成功。対象限定承認後、guestへ検証・導入してplain-clickを1回開始したが、event-post preflightで停止した。Fixture起動・入力送信前で、配送境界の新たな実測はない。権限変更・再試行・修飾入力・Tabbed E2Eは行わず、Harnessを通常終了。旧版・全ログ・未保存書類・隔離設定を保持した。[停止結果と限定試験案](Tests/guest-e2e/README.md)を参照。

その後、同一0.7のguest権限再登録とplain-click 1回への個別承認後、正規設定UIでHarnessだけを再登録した。preflightは通過し、tag付きdown/upはFixtureのAppKit local monitorへ到達したが、両方windowNumber=0/window=nilで期待する窓の入口には記録されず、input.json不在で停止。アプリに届く前の不達ではなく、window割当/振分けが次の対象となる。修正・再送・⌘操作・本体E2Eは行わず、専用アプリを正常終了してログと隔離を保持した。[配送境界の実測](Tests/guest-e2e/docs/build-result-20261021.md)を参照。

0.8は、process宛てmouse eventに公開window fields91/92で検証済みAのIDを指定する最小候補を準備した。105 assertions・媒体判定25ケース・両型検査/build/署名/実ISO往復が成功。固定PID/windowと安全領域、受信gate、release/watchdogは維持。session切替・非公開field・Fixture内の強制配送は加えない。効果はguest未実証で、次の対象は完成成果物の導入・必要なら同Harnessのguest許可再登録・通常click 1回に限定する。[成果物・根拠と停止条件](Tests/guest-e2e/README.md)を参照。

その後の対象限定承認により0.8をguestへ導入・検証し、同Harnessだけを正規UIで再登録して通常clickを1回実行した。window fields91/92はAppKit受信まで期待IDのまま保持されたが、NSEventはwindow0/nilのままでNSWindow入口へ記録されず、input.json不在で停止。2fieldだけでは解消しないことを確認し、追加field/別経路/再送/新版には進んでいない。専用アプリを通常終了してログ・旧版・未保存書類・隔離を保持した。[実測結果](Tests/guest-e2e/docs/build-result-20261021.md)を参照。

```sh
bash Tests/test.sh           # 段階1のみ。アプリ・VMは起動しない
bash Tests/test.sh help      # 他の明示的な入口を表示
```

VM準備・実行の詳細は [Tests/guest-e2e](Tests/guest-e2e/README.md)。0.2は権限再登録後に入力前のAX/CG座標照合で停止し、入力配送とE2Eは未確認。[実測記録](Tests/guest-e2e/docs/guest-smoke-v02-result-20261021.md)。0.3の安定観測とhit判定を含む成果物は保全済みだが、ゲスト未実行。[調査記録](Tests/guest-e2e/docs/geometry-investigation-20261021.md)。0.4の個別probeが成功してもsession tap/Tabbed受理の確認とはしない。

> Local fork work: `sugitach/tabbed`, branch `fix/restore-windows-on-quit`, based on `9481b628767921bd1af1b90c4d7448282c9757b6`. Normal Quit now attempts to restore all grouped windows after stopping monitors. SDK 26.5 typecheck/build, seven standalone non-GUI policy tests, ad-hoc signing and archive/media round-trip checks passed. User-reported VM retests passed for normal Quit with one two-window group and with two groups (2026-10-21); edge-case runtime tests remain pending. See [build results and transfer steps](docs/build-validation.md). See [investigation, validation, and VM retest plan](docs/quit-restoration.md).

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
