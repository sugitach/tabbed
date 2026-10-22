# Guest E2E harness (0.11)

## main起点のテストと非GUI回帰

現在のテストブランチはmainから直接分岐し、Sourcesへの本体修正を含まない。内部回帰は `bash Tests/test.sh internal`、guest手順の表示は `bash Tests/test.sh guest help`。guest側の実行は終了のままで、未完了E2Eの成功を新たに宣言しない。

内部18ケースは通常Quitとprune等の振る舞いを確認する。実際のAppDelegate終了メソッド、controller/AXメソッドを存在する場合だけ原文のまま抽出し、AX/UI/画面と通知の境界を模擬する。mainに任意の終了コールバックがない場合、モデル化した通常終了は何も復元せず、その結果をテストで失敗とする。欠けた復元メソッド/ポリシーの代替実装は置かない。isKnownClosedを直接呼ぶテストもpruneの結果で検証する形に変更した。

旧WindowRestorationTestsの7ポリシーケースは、同じ要件を通常Quitの結果で確認する7ケースへ置き換え、既存11ケースと合わせて18ケースをCLTで実行する。XCTestのWindowRestorationTestsは同じCLIを起動して終了コードを検査するアダプターとし、新しい本体型へのビルド依存をなくす。CLTのアダプター型検査には宣言のみのXCTest shimを使うため、フルXcodeでのXCTestビルド/実行済みとはしない。

修正前の回帰失敗でも、コンパイル/テスト実行/本体型検査の終了コードを別々に記録する。Sources snapshot、任意メソッドの有無、抽出原文、コマンドと結果はignore対象のRegression/resultsに保存。これは実NSApplicationライフサイクルや実AXの試験ではない。実OSでの入力受信やgroup/Quit結果は、以下の別のguest実測記録だけを根拠とする。

## 履歴: 最初の積み上げ型保存（2026-10-22）

このテスト実装と実施記録は `test/window-restoration-and-guest-e2e` に保存した。同ブランチは `fix/restore-windows-on-quit` → `fix/retain-windows-on-ax-errors` の両修正を含む。`main` へは統合していない。内部回帰は `bash Tests/test.sh internal`、guest手順は `bash Tests/test.sh guest help` が入口。

ユーザー指示によりVMでの調査・実行は終了した。以下の「次の試験」「承認待ち」は当時の履歴で、再開指示ではない。最新0.11の本体E2Eはgroup後の解放状態検査で停止し、全体PASSではない。分割時の再検証は純粋判定176件/媒体ポリシー25件と構文確認のみで、GUIアプリ・VMの起動/入力/権限変更は行っていない。成果物・生ログはignore対象としてローカル保持し、このブランチにはソース・手順・転記した結果記録のみを含める。

## 最新実測: group操作後の解放状態検査で停止

ユーザーの継続承認を受けauto-addを正規メニューでOFFにし、同一導入済み0.11の新run `AE049562-C67F-4431-809E-B26CBED2FB4E` を1回開始。groupの⌘ドラッグ後に `E2E session reports a held modifier / left mouse` で停止した。mouseUpとCommand解放の送信、FixtureでのCommand=false/flags=0受信は記録されたが、combinedSessionStateのどの項目が残ったかは未記録。画面上のスタック表示だけでgroup検証成功とはしない。解除/regroup/通常Quit/復元は未実施。最初の失敗後はログ読取りだけで、3app/窓を保持。新build・権限変更・再送なし。[詳細とログhash](docs/build-result-20261021.md#011-auto-add-off後の再実行group後の解放状態検査で停止)。

## 履歴: 0.11初回E2Eはauto-add ONで入力前停止

同一固定ISOをguestへ接続し、read-onlyと素材/全bundle hash・3app署名を確認して導入した。正規Settingsで同Harness/Tabbedだけを再登録し両方ONを確認。E2Eはrun `69606CAA-61FB-4CAE-81D3-8D16541B61CF` の1回だけ開始し、`Tabbed auto-add preference is ON; no preference was changed` でpreflight停止した。Fixture PID=0、target PID=0、frames/checkpoints空。入力・group/解除/regroup/Quitは未実施。最初の失敗で止め、auto-add変更・再試行・build変更はしていない。

Harness PID6616は結果表示だけを残し試験taskは終了。Fixture/Tabbedのpgrep一致なし。未保存TextEdit、旧2app・全ログ、read-only媒体、既存のguest許可、host/隔離を保全。guest権限はHarnessの事前検査を通過したが、Tabbed自身の実アクセスは本体未起動のため未実証。[導入・権限・停止ログとhash](docs/build-result-20261021.md#011-guest導入許可更新と初回preflight停止)。以下は準備と過去の履歴。

## 0.11完成: 本体を用いた単独E2E（guest実行承認待ち）

[固定ISO](exports/20261021T101722Z/Tabbed-Guest-Harness.iso)（SHA256 `e06a4a04ccb046d4ffa5980b409fcfd4e24bb10e93a135e29d6cdc36fca31335`）。Harness/Fixture 0.11.0 build11、本体0.1.2 build3。176 pure assertions・媒体25ケース・3app型検査/build/署名と実ISO往復が成功。本体実行ファイルSHA256 `a0160cdd0579b8cd85a7dcc520e7c9db812989d5fef9679e0c1972427778b064`。署名済み本体とコンパイル時pin・resource pinの一致、元の本体ソース不変も確認。GUIアプリはホストでもguestでも今回未起動。[全hash・検証と承認範囲](docs/build-result-20261021.md#011最終成果物と実行承認待ち)。この完成追記は固定SOURCE.ZIP生成後の記録。

次の承認対象は、この同一ISOをTabbed-Testへread-only導入し、旧2アプリと全ログを保全してhash/署名を検証、必要なら同Harness/Tabbedだけのguest AX/event-postを正規UIで再登録し、`run e2e` を1回だけ実行すること。最初の失敗で止め、host権限・隔離設定は変更しない。実行中はguestを操作しない。今は承認待ちであり、導入や権限変更もまだ行わない。


`bash TEST.SH run e2e --confirm-isolated-guest` が、同じ専用Fixture2枚でグループ化→⌘ドラッグで引き出して解除→再グループ化→通常メニューQuit→共通group frameへの復元を一連で確認する。通常click/Cmd probeは前置しない。xによる解除・一時AX失敗のfault injectionは対象外。本体ソースは変更せずsnapshotからビルドし、署名済みコピーのhashをHarnessへ生成・固定する。新0.11はまだguest未導入・未実行。通常strip設定が必要で、auto-add/compactがONなら設定を変えず停止する。下記の0.10成功は保全する。

ホスト入口 `bash Tests/guest-e2e/test.sh host` は本体/Fixture/Harnessの型検査・arm64 build、純粋テスト、別コピー署名、read-only ISOと実往復検証まで。GUIアプリは起動しない。SDK26.5、deployment macOS14、guest想定は前回実測のmacOS26.6.2。OS実操作成功はこのホスト検証から推定しない。

媒体には従来のHARNESS.ZIP/SOURCE.ZIP/BUNDLE.SHAに加えてTABBED.ZIP/TARGET.SHAが入る。旧guestの両固定ディレクトリを明示的に別名保全した後、`prepare`、`prepare-target` の順に実行する。既存先への上書きは拒否する。どちらも媒体read-only・hash・署名を検証し、起動/権限変更はしない。prepare-targetは新Harnessの生成pinとも照合する。

各入力は0.10のsession配送・⌘押下と解放の分離・3秒watchdogを使用。始点と各分割点を現在のAの実AX blank content/CG frame/AX hitで確認する。Aを少しずつ移動させるので、空き位置へ向かう場合も、入力前の各点はまだAの内側でなければ停止する。DockのCG boundsやAX/CG全矩形一致には依存せず、drop indicatorもAX hitを隠せば停止し例外で通さない。安全確認後の前面変更など競合は残るため実行中にguestを操作しない。

`e2e-checkpoints.json` とdriver/resultへ同一PID/窓ID/identifier、別々のAX/CG値、最小化/on-screen、visibleFrame/scale、段階と時刻を保存。グループ化時は本体所有の既知frameの通常stripが一意に現れ、解除ではそのwindow IDとstrip候補が消えることも確認する。各条件は3回/0.3秒以上の安定観測、Quit後は3回/計0.9秒で再退避なしを要求する。Quitは初期の別々の位置でなく、直前group frameへ2枚を戻す契約。1回でも失敗したら入力を解放して停止し、後続操作/再送/強制終了/AX修復はしない。観測待ちは入力の再試行ではない。

成功時は対象Tabbed PID終了とtap消失、元の2枚の生存・可視復帰を確認してから自前Fixtureを正常終了し、Harnessも通常終了する。scriptはresultのrun/mode/PASSと3つの記録PIDの消失まで確認して終了コード0。失敗時は窓/アプリと証拠を保持する。追加の権限要求は自動承諾せず停止。必要なguest権限はHarnessのAX/event-postと本体のAX（既存のevent tap用途）で、Fixtureにグローバル権限は不要。新しい種類の権限、host設定、network/共有/clipboard/clean複製は変更しない。

## 最新結果: 0.10のCommand操作は各1回PASS

導入済みの同一0.10を、ユーザー本人の直接確認後に実行。`command-click`（run `08A0466A-119B-4F81-BF95-7EFB6ADBAF47`）がPASSし、正常終了を挟んで `command-drag`（run `0EDC22C2-DE88-42D6-B9FE-4764B226CCE6`）もPASSした。tag付き⌘押下→down→（drag）→up→⌘解放、raw flags1048576→0、Aの空白viewでの予定座標とログ保存を確認。追加の導入・build・権限変更・再送は行っていない。

Harness/Fixtureは正常終了し、最終pgrepでHarness/Fixture/Tabbed一致なし。未保存TextEdit・guestログ・既存権限・read-only媒体・隔離を保持した。今回の成功は専用Fixtureへの合成入力受信で、Tabbed本体の受理・グループ化・解除・Quit復元やホストからの⌘転送は未検証。[run・受信根拠・ハッシュ](docs/build-result-20261021.md#追記-010のcommand-clickとcommand-drag成功)。以下の審査拒否や未実行は実行前の履歴。

## 履歴: 段階3の初期準備案（0.11実装前）

**以下は実装前の検討履歴。上の0.11が現仕様で、解除はxでなく実ドラッグによる引き出しを採用した。旧0.10のE2Eボタンは実行しない。** 通常clickやCmd probeは繰り返さない。現在のE2Eは解除を含まず、古いAX/CG全矩形一致とCG重なり順のguardを使うため、段階2の成功をそのまま適用できない。本体の固定hashも一時AXエラー対策前のもの。以下を最小の次期E2E実装仕様とする。今回の作業は読み取り・署名/hash・shell構文の静的確認と文書更新までで、新コード/build/媒体/guest操作はない。

| 順序 | 操作と期待値（すべて同じrunのFixture A/B） |
| --- | --- |
| 0. 基準保存 | 固定署名/hash/PID・2枚のCG ID/AX identifier/title、各初期frame、非最小化/on-screen、guest画面/visibleFrame/scale、入力解放を記録。`fixture.json`に加え実AX/CGの同時点値をdriverログへ保存。既存Tabbedなし・auto-add OFFを確認し、設定は書き換えない。 |
| 1. グループ化 | 検証済みTabbedを起動しtap準備を確認。Aの空白contentからBの空白contentへ⌘ドラッグを1回。修飾押下/待機/down/drag/up/待機/解放を分ける。AがBの直前frame、Bが画面外へ退避し、同じ2枚が生存することを外部観測。単なる重なりだけでは合格にしない。 |
| 2. 解除 | Tabbed所有の該当タブstripとAの解除用xを一意に確認して1回操作。A/Bとも生存・非最小化・on-screen、strip消失、Bはgroup frame、Aはその右下32pt（Quartzではx+32/y+32）に復帰することを確認。これは本物のウィンドウcloseではない。 |
| 3. 再グループ化 | 同じA/Bを、現frameから新たにAX hitで確認できる空白開始点/終点で1回だけ再グループ化。2の重なりで安全な開始点が取れなければ入力せず停止。1と同じ外部条件を確認し、その時点の共通group frameをQuit期待値として保存。 |
| 4. 通常Quit | 検証済みTabbed PIDの正規status menu→厳密な `Quit Tabbed` をAXPress。正常終了を待ち、同じ2枚がgroup frame内に生存・非最小化・on-screenで戻り、3回/計0.9秒で再退避しないことを確認。Tabbed PID終了・tap消失・新たなTabbedの不在も判定する。 |
| 5. 記録と終了 | run/modeに一致するresult、各段階frame/visibility、送信audit、入力解放と残留を保存。成功時のみ明示cleanupで自前Fixture/Harnessを正常終了し残存なしを確認。失敗時は入力解放後、ログと窓/Tabbedを保全して停止し、強制終了・復旧AX移動・再送はしない。 |

初期位置は証跡であり、Quitの期待値ではない。現実装のQuitは「作成時のA/Bの別々の位置」へ戻す処理ではなく、直前の共通group frameへ2枚を重ねて戻す。誤った期待値で復元を失敗扱いしない。AX値とCG値は別々に保存し、同一PID/ID・現在の安全領域・point hitで入力先を確認する。数ポイントの矩形差そのものを失敗根拠にせず、同一windowの複数回安定観測を使う。Dockを無条件除外する変更やクリック可能性をCG bounds返却順だけで決める変更はしない。

### 実装前に確定した不足と停止条件

- `test.sh run` / `GuestInvocation` にE2E入口はなく、現0.10はUIボタンのみ。次期版に単独の明示シナリオとrun/mode照合を追加する必要がある。既存smoke/probeを自動前置しない。
- 旧E2Eの `waitForStableGeometry` / `validateEventPoint` は段階2の既知の停止条件を保持し、入力leaseの区切りも旧式。実証済みsession経路と分離した⌘押下/解放を再利用するが、Tabbedのドラッグ中にはA自体が動き、drop indicatorがBを覆う。旧Aの固定位置やA/B両方のAX hitを全時点で要求するだけでは成立しない。取得済みmouse leaseを同一runに限定し、目的点Bの実AX hit・位置・overlay所有者を根拠に確認できない場合は解放して停止する。未知のoverlayは許容しない。
- `TabItemView` のxはhover時だけ生成され、明示AX label/identifierがない。静的ソースだけでは対象Aのxを一意選択できると保証できない。guestで正規AX/画面から特定できなければ解除前に停止。座標推測、任意button選択、内部untab直接呼出し、本体へのテスト用API追加は行わない。この制約下で完全自動解除はまだ未実装。
- Tabbedはtakeover後のdrag/upをtapで消費するため、段階3でFixtureに0.10と同じ完全受信列を要求しない。送信auditと全入力解放、外部のgroup/解除/復元を判定する。0.10の受信成功をTabbed受理成功へ置き換えない。
- 最初の署名/権限/入力先/操作/観測/ログ保存の失敗で止め、後続操作や自動再試行をしない。失敗時の「未実行」と「送信後結果不明」を分ける。復元失敗alertが出た場合も追加操作はしない。

次の実行承認は、完成後の具体的hashを示した①一時AX対策を含む最新Tabbed成果物と次期Harnessのguest導入/起動、②必要な場合だけその2アプリのguest AX/event-post再登録、③上表の2回のグループ化・解除1回・通常Quit1回と専用アプリの正常cleanupをまとめて対象とする。新しい権限種類は対象外。session入力の確認後に前面が変わる競合があるため、その間はguestを操作しない。今回はその実行を求める段階ではなく、完成hashもまだない。本体コード・host設定・隔離・clean複製・未保存書類を保護する。ログはguest内に保持しCUA画面で読み取る。rawログのhostへの回収が必要なら、共有/ネットワークを有効化せず別のread-only媒体化手順を後で確認する。

## 現在の状態: 0.10導入・許可更新済み、実行直前で審査拒否

対象ISO `exports/20261021T092202Z/Tabbed-Guest-Harness.iso` を検証してTabbed-Testへ接続し、guestでもZIP/全素材ハッシュ・両appのstrict署名検証を通した。Media Read-OnlyとVolume Read-OnlyはいずれもYes。旧0.9は `~/tabbed-guest-harness-test-v09-099bbb80` へ移して保全、新0.10は固定パス `~/Tabbed-Guest-Harness-Test` へ導入。guestの正規設定UIで同Harnessだけを再登録し、Harnessと既存Tabbed Quit Fixの両スイッチがオンと確認した。

その後、Command-click1回の起動コマンドをguest Terminalへ送る操作が自動承認審査で拒否された。理由は「ユーザー製0.10を実行しCommand-clickを送る操作について、assistant/delegationの承認伝達だけでは直接信頼できるユーザー確認が見えない」。拒否後の画面でもTerminalはprepare後のプロンプトのままで、起動コマンド未入力、Harness/Fixture未起動。0.10のpreflight・Command-click・Command-drag・受信判定はすべて未実行。再試行や別経路実行は行わない。必要なのはこの実行範囲に対するユーザー本人からこのチャットへの文字による確認で、導入・権限更新の反復ではない。未保存書類・旧ログ・隔離設定は保持した。以下は準備時点と過去の記録。

## 0.10媒体完成、Command試験は承認待ち

[読み取り専用ISO](exports/20261021T092202Z/Tabbed-Guest-Harness.iso) を作成した。SHA256 `05b877d4c84a5871a47946655d1fcfaac05f71f2de96a491f50e605f266dea30`。ホストの純粋143 assertions・媒体判定25ケース・両appの型検査/build・ad-hoc署名・実ISO往復検証は成功。ホストでHarness/Fixtureは起動していない。Command操作の実OS受信は未確認で、guest導入/実行/権限変更も今回未実施。直前の0.9通常click1回の成功と承認は保全する。

次の具体的対象は、この同一0.10をTabbed-Testへ導入・検証し、必要ならguestの同HarnessだけをAX/event-post一覧へ再登録して、⌘click1回、成功した場合だけ⌘drag1回を実行すること。どちらも自前Fixtureの空白view内、最初の失敗で止める。session全体への修飾入力なので、確認後に前面が変わると別の場所へ届く競合が残る。実行中のguest操作は避ける。ホスト権限・隔離設定・Tabbed本体は対象外。具体的な実行時承認前には進めない。以下に手順と判定を記す。この完成報告はbuild後追記のため、固定SOURCE.ZIP内には含まれない。

## 次段階: 0.10のCommand操作を準備（guest未実行）

通常session clickの実受信成功を踏まえ、0.10は `command-click` / `command-drag` も同じsession経路にそろえる。今回の準備はホストでの実装・非GUI検証・署名媒体作成まで。0.9の通常click1回の承認は、新版やCommand操作には拡張しない。次の具体的対象は完成した同一0.10の導入・必要な同Harnessだけのguest AX/event-post再登録・Command-click1回、成功した場合だけCommand-drag1回。最初の失敗で止め、再送・本体E2Eへ進まない。

各試験は専用Fixtureを前面にし、署名/hash/run ID/PID/window ID・画面/scale・AX hit・現在の空白領域/CG枠内を送信前に検査する。通常clickと同じ安全確認を、⌘押下前・mouseDown前・drag前・mouseUp前・⌘解放前に行う。session入力はPIDに限定されず、確認後に対象が変わる競合が残るため、実行中はguestで他作業をしない。既存の3秒watchdogとrun全体75秒制限を維持する。停止時は実際に押下を試みた分だけを解放し、mouseUp後の待機中ならCommandUpだけを送る。プロセス/OS停止・権限失効時の配送自体は保証できない。

順序は⌘押下→0.12秒待機→mouseDown→0.12秒待機→（dragなら同じ空白view内を右へ30pt移動し0.12秒待機）→mouseUp→0.12秒待機→⌘解放→0.3秒待機。追加文字キー、cursor warp、受信handlerの直接呼出しは加えない。

合格にはtag付きのflags(Command=true)→down→（drag）→up→flags(Command=false)の厳密な列と時刻順序が必要。マウスは同一A、flagsは同じrunのFixture A/Bだけを許可する。Commandのboolとraw flagsを照合し、Shift/Control/Optionの混入、押下/解放欠落や順序不正を失敗にする。受信content座標はclickが同一点、dragが予定の30pt移動と終点upを0.5pt以内で示し、blankHit=true、受信ログの書込み完了まで要求する。raw flagsはinput.jsonへ追加し、DeliveryTraceにも従来どおり記録する。結果modeは `SESSION_INPUT_PROBE_command-click` / `SESSION_INPUT_PROBE_command-drag`。

実行入口は次の2つ。各run終了後は専用CloseでFixture、通常CloseでHarnessを終了してログを保持し、前の専用プロセスが残っていないことを確認する。2番目は1番目のPASSを確認できた場合だけ実行する。単独test.shは入口だが、初回の媒体接続・ログイン・guest許可・run間の正常終了まで完全自動化したとは扱わない。

```sh
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run command-click --confirm-isolated-guest
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run command-drag --confirm-isolated-guest
```

以下は0.9以前の実測と履歴。

## 最新結果: 0.9のsession通常clickが成功（2026-10-21）

ユーザー本人の、このチャットでの具体的な文字による実行承認後、同一導入済み0.9を1回だけ実行した。run `099BBB80-EA09-42B3-A335-FE9E0F45B75D`、mode `SESSION_INPUT_PROBE_plain-click`、結果 `PASS`。権限preflightと送信前AX hit確認を通過し、Fixture PID5223のA/window564にtag付きdown/upが各1件届いた。両方Command=false、content(180,119)、blankHit=true。local monitorとNSWindow入口のwindowNumber/windowは564で、受信gateのaccepted=trueとinput-write-okのreceiptCount=2を確認した。通常session経路で専用Fixtureがこのクリックを受信・保存したことが今回の確認範囲である。

FixtureとHarnessを通常終了後、guestのpgrepでHarness/Fixture/Tabbed一致なし。未保存TextEdit、旧成果物/ログ、隔離を保持。ログはguestの `~/Library/Application Support/TabbedGuestHarness/099BBB80-EA09-42B3-A335-FE9E0F45B75D/` に保存。⌘操作とTabbed本体E2Eは未実施。[受信根拠・ハッシュ・終了状態](docs/build-result-20261021.md#追記-09のsession通常click成功)。以下の停止記録とguest未実行の記述は、このrun以前の履歴として残す。

## 履歴: 0.9 guest導入後、実行前に停止

対象ISO `exports/20261021T081412Z/Tabbed-Guest-Harness.iso` のホストSHA256を再確認し、Tabbed-Testへ接続した。UTM管理画面は従来と同じ「開けませんでした」通知を出したが、guestの `HARNESS.ZIP` SHA256はマニフェストと一致し、媒体の Media Read-Only / Volume Read-Only はいずれも Yes。旧0.8固定インストールは `~/tabbed-guest-harness-test-v08-a8d8df5b` に移して保全し、媒体の `test.sh prepare` で新0.9を固定パスに検証・展開した。ファイルハッシュと両アプリの厳密署名検証は成功した。Guestの設定UIで旧Harness項目だけを外して固定パスの新Harnessを再登録し、HarnessとTabbed Quit Fixの両方がオンと確認した。

このあと承認済みの通常click 1回用コマンドのGUI入力が自動承認審査で**拒否**された。審査の理由は「ユーザー製ISO由来の未認識ソフトの実行は、実行時点の新しい確認が必要」というもの。経路を変えた再試行はしていない。拒否後のguest画面ではTerminalのプロンプトがそのまま残り、試験コマンドの入力もアプリ起動も見えない。従って0.9のpreflight/Fixture起動/入力送信/受信は**未実行**で、成功・失敗いずれの実測もない。今回の承認はインストールと同Harnessのguest許可再登録まで実施できたものとして記録する。未保存TextEdit、旧成果物とログ、VMの隔離設定は保持。必要なのは同一0.9の固定成果物のゲスト実行に対する実行時の明示確認であり、追加ビルド・権限拡大は対象にしない。

追記: 具体的な再確認へのowner反応を上位タスクが検証したとの連絡を受け、同じ起動コマンドを**1回だけ**再試行した。自動承認審査は再び拒否し、理由を「assistant/delegationによる承認の主張では、この実行に対する直接信頼できるユーザー確認が見えない」と明示した。別経路での実行・追加再試行は行わない。再拒否後の画面も同じTerminalプロンプトで、試験コマンド未入力・Harness/Fixture未起動。上記の「未実行」が現在の確定状態である。

## 完成媒体（0.9、guest未実行）

[ISO](exports/20261021T081412Z/Tabbed-Guest-Harness.iso) SHA256 `e7f28a952e388ff4a77e5707f10be04dc925bbbba323953329c8e2a4a787b699`。ホストの純粋111 assertions・媒体25ケース・両app型検査/build/署名・ISO往復が成功。[完成記録と次の対象](docs/build-result-20261021.md#09-媒体完成2026-10-21guest未実行)。この段落はbuild後追記。

## 再開後の最小試験（0.9、guest未実行）

`plain-click` だけを通常の `CGEvent.post(tap: .cgSessionEventTap)` に変更する。down/up各1回、Commandなし、cursor warp/mouseMovedなし、window fieldsの追加なし、再送なし。⌘click/dragは従来のprocess経路を保全しているが、次の実行対象に含めない。Tabbedも起動しない。

送信直前に署名/hash・run ID/PID/window ID・前面アプリ・画面/scale・CGの同一ID/owner/on-screenを検証し、点が現在のAX空白contentとCG枠内の両方に属することを確認する。system-wide AX hitが同一PIDの同一AX windowを返すことを必須にする。AX windowはrun固有identifier/title/role/subroleで特定する。AX/CG全矩形の一致は要求せず、DockのCG全画面boundsやlayerを実hit判定として使わない。権限不足やhit不明は入力前に停止する。

session入力はPID限定ではなく、確認から送信までに前面/遮蔽が変わる競合は残る。guestで他作業をせず、既存release/watchdogを維持する。Fixtureの受信gateと出力経路は変更しない（歴史的な `--process-probe` 名は受信制限の選択として再利用）。正しいtag・Aのwindow・content/blank hitでdown/upが受信され、receiptとtraceの書込み完了まで確認できたrunだけPASS。結果modeは `SESSION_INPUT_PROBE_plain-click` であり、修飾入力やTabbed成功ではない。

次の対象は完成した0.9の導入・guestの同Harnessだけに必要なAX/event-post再登録・通常click 1回。ホスト権限、隔離設定、他アプリの許可は変更しない。最初の失敗で止め、媒体・署名・新規runのログを保持する。未確認のOS配送成功は宣言しない。ホストでは型検査/build/純粋テスト/署名/ISO往復だけを行い、アプリは起動しない。以下は版ごとの履歴であり、現在の経路・未実施状態はこの節を優先する。

## 最新結果: 0.8の公開window fields指定だけではwindow未割当を解消せず

対象限定承認後、同一0.8を検証・導入し、guestの同Harnessだけを正規UIで再登録してplain-clickを1回実行した。run `A8D8DF5B-1765-4E1B-813E-3788DF2ABEEF`、preflight通過、Fixture PID4641/A522/B523。指定したwindow fields91/92=522はtag付きdown/upのAppKit local monitorでも保持されていたが、両方ともnsWindowNumber=0/nsEventWindow=nilのまま。対応するNSWindow入口/gate/writeの記録はなく、input.json不在で失敗停止した。

このVM条件下では2fieldの指定だけでは十分でなかった。追加field・非公開API・session切替・再送・新版作成へ進まず停止した。専用CloseでFixture、通常CloseでHarnessを終了し、最終pgrepでHarness/Fixture/Tabbed一致なし。未保存書類・旧版・全ログ・隔離を保持。権限変更はguestの同Harness再登録だけで、host/他アプリは不変更。⌘操作と本体E2Eは未実施。[観測・保存ログ・残存状態](docs/build-result-20261021.md)。

## 0.8の設計と準備（以下は実行前の記録）

**ホスト検証完了:** `exports/20261021T071804Z/Tabbed-Guest-Harness.iso`、SHA256 `60ac90f3c92d5b35a5feb54f034179b726f282e3b66f52107b5e8e86858ca4a2`。両型検査/build、105 assertions、媒体判定25ケース、署名・実ISO往復を確認した。[全ハッシュと検証記録](docs/build-result-20261021.md)。この完成結果は媒体snapshot後の追記。guestは未導入・未実行。

0.7でtag付きmouse down/upがFixtureのAppKitまで届いた一方、window=0/nilだった。0.8ではprocess probeのmouse down/drag/up（watchdogによるupも含む）に、検証済みFixture Aの同一window IDを `.mouseEventWindowUnderMousePointer` / `.mouseEventWindowUnderMousePointerThatCanHandleThisEvent` へ設定する。これが唯一の配送に関する変更。正のPIDと非ゼロwindow IDの両方を必須とし、片方だけなら生成前に停止する。sessionへのfallbackは設けない。

2つのfieldはSDK26.5 CGEventTypes.hで91/92、「10.7で公開」とされる定数で、[Appleの列挙API](https://developer.apple.com/documentation/coregraphics/cgeventfield/mouseeventwindowundermousepointer)にも存在する。既存の[PID宛て実装](https://github.com/rlmsinclair/claude-on-second-display/blob/main/claude_on_second_display/pid_events.py)もmouse eventに同じwindow IDを設定する。ただし同実装のclickは事前mouseMovedとclickCount設定も行うため、今回の2fieldだけで十分という実証ではない。同リポジトリの「undocumented」という表現より、APIの公開性はSDKの宣言を根拠に判断した。未知の数値field、非公開window-location setter、SkyLightは使用しない。

**postToPidにwindow指定が普遍的に必須とは断定できない。** CGEvent.hは指定アプリのstreamへ配送し、annotated session tapから他processへ振り分ける用途を例示するが、window引数や生成したmouse eventへの自動window割当の保証はない。今回の未割当という実測に対する、公開window metadataの最小検証候補である。通常の座標操作には[Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap_event.m)のCGEventPost(kCGSessionEventTap)、[cliclick](https://github.com/BlueM/cliclick/blob/master/Actions/ClickAction.m)のHID tapという先例がある。これらはOSの通常の座標/前面/遮蔽の振分けを使う全体入力で、固定PID宛てとは別の保証範囲になる。今回sessionへ切り替えず、まずPID/windowの制約を保つ。

Fixture handler・gate・判定は0.7と同じで、直接NSWindow/NSViewを呼んだり、受信eventのwindowや座標を書き換えたりしない。予定CG点、tag、pause、実カーソル、modifier送信、release/watchdogは変えない。既知ID/PID/署名/前面/画面/安全領域の送信前確認と、受信側のA/blank hit確認を維持する。source hash・署名媒体は新しい0.8として固定し、全旧版/ログを保持する。

次の確認対象は **完成した同一0.8をTabbed-Testへ導入・検証し、必要な場合はguestのこのHarnessだけを正規UIで再登録して、plain-clickを1回だけ実行すること**。権限対象をこのアプリに限定し、host・他アプリ・新種類の権限を含めない。最初の失敗で停止し、windowが依然0/nilなら未知fieldを足し続けず、session経路を使うか設計から判断し直す。新たな警告や範囲外の権限要求でも停止する。⌘操作・本体E2E・自動再送は含めない。0.8のguest導入/実行/権限変更は今回未実施。

合格にはtag付きdown/upが期待するNSWindow入口→gate→writeに到達し、従来receipt判定とtrace書込完了確認が通る必要がある。AppKit monitorにwindow番号が出ただけではPASSではない。成功してもprocess transportの通常clickだけの結果で、session tapやTabbedの受理は未検証のまま。

## 最新結果: 0.7再登録後、AppKitに届くがwindow未割当

同一0.7のguest入力送信権限再登録とplain-click 1回への対象限定承認後、正規設定UIでHarnessだけを再登録した。preflightは通過し、run `7E7E4FCC-BA5D-4785-94B1-F017EA9C67B9` のFixture PID4124へdown/upを1回ずつ送信。input.json不在で停止した。

今回の診断では、同じtag付きdown/upがFixtureの **AppKit local monitorまで到達** したが、両方 `nsWindowNumber=0` / `nsEventWindow=nil`。期待するAはwindow477で、そのmouse eventのwindow-entry、receiver-decision、input-writeは記録されていない。通常のAppKit-defined eventではwindow477/478のwindow-entryがある。したがって今回はアプリへの配送不在とはせず、AppKit内のwindow割当/振分けを次の切り分け対象とする。原因・必要なfield/API・修正方法は未確定。再送や新版作成は行っていない。

専用CloseでFixture、通常CloseでHarnessを終了し、最終pgrepでHarness/Fixture/Tabbed一致なし。ログ・旧版・未保存書類・隔離を保持。権限はguestの同Harnessの再登録だけで、host権限・他アプリ・network/share/clipboardは変更していない。⌘操作と本体E2Eは未実施。[観測値と保存ログ](docs/build-result-20261021.md)。

## 直前の結果: 0.7導入時はevent-post preflightで停止

同一ISOへの対象限定承認後、guestの媒体ZIP hash、Media/Volume Read-Only、全媒体マニフェスト、展開後全bundle hash、両strict署名、実行ファイルSHA256を確認して固定パスへ導入した。旧0.6は `~/tabbed-guest-harness-test-v06-af77dc2e` に上書きせず保全した。

`plain-click` の開始は1回だけ。run `6A1BB027-42F8-427C-A53B-6BD9E92A2418` は `Guest event-post permission missing. No request or setting change was made.` で停止。Fixture起動・入力生成/送信前であり、各配送境界の検証は未実施。権限再登録・再実行・修飾入力・Tabbed E2Eは行っていない。Harnessを通常終了し、最後のguest pgrepでHarness/Fixture/Tabbed一致なし。旧ログ・未保存TextEdit・隔離設定は保全。これは権限不足による失敗停止で、実行中や認証/承認待ちではない。[停止ログと残存状態](docs/build-result-20261021.md)を参照。

## 0.7配送観測の設計（以下は導入前の計画）

**ホスト検証完了:** 出力は `exports/20261021T062123Z`、ISO SHA256 `8190e9bde9776d9ce282c86ff3f69df833205eda685458627e2433ee7cf77a39`。98 assertions、媒体判定25ケース、両型検査/build/署名/実ISO往復が成功。[全ハッシュと検証記録](docs/build-result-20261021.md)。この完成結果は媒体snapshot固定後に追記した。後続のguest結果は上記参照。

0.6の通常入力対照はprocessProbe=falseであり、専用modeのgate・追加JSON項目の出力成功までは証明しない。次は **plain-clickを1 runだけ** 実行し、同じCGEvent生成・postToPid・受信gate・待機時間を保って観測だけを加える。session経路への切替、windowフィールドの設定、mouseMoved、cursor warp、追加権限は行わない。⌘入力とTabbed本体は含めない。

送信直前/返却直後のtype・tag・PID/windowフィールド・CG座標をメモリに保存し、解放後にdriver.jsonlへ書く。実カーソルのAppKit座標も前後で読む。Fixtureのprocess専用modeに限り、自アプリのlocal monitor→NSWindow入口→受信判定→input.json encode/atomic writeを `fixture-delivery.json` に記録する。最大128行、文字列metadataだけで、入力文字・key code・他アプリの内容は収集しない。monitorは元のイベントをそのまま返す。初期出力/monitor準備をhandshakeで要求し、書込み失敗や上限到達ではFixtureを終了する。PASSには従来のreceipt判定と全receiptのwrite完了記録を要求する。leaseのlock内にファイルI/Oを置かず、既存watchdog/releaseを保つ。

判別: local monitorにtag付きdown/upがあり窓入口にないならAppKit内のwindow routingを疑う。窓入口まで来ればtype/window/tag/content座標とgateを照合する。write-startだけならencode/write経路、write-okがあればdriverの読取・判定を確認する。local monitorにもなければ、それ以前の配送/変換が候補に残るが、OS配送失敗とは断定できない。全受信・出力と従来判定が通れば、そのrunのprocess宛て通常クリックだけが成功。session配送・修飾入力・Tabbed成功にはしない。失敗後の再送やAPIの同時切替はしない。

根拠: Appleの[イベント構造](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventArchitecture/EventArchitecture.html)ではWindowServerのwindow付与、NSApplication dispatch、NSWindow dispatchは別段階。[local monitor](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)は自アプリdispatchの観測であり、WindowServerや最初のprocess受信点ではない。SDK26.5 CGEvent.hのpostToPidはvoidで受信ACKを返さず、mouse生成位置はglobal座標。公開field 91/92の存在から手動設定必須とは判断しない。[カーソル移動API](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/MouseCursor.html)はmouse event生成とは別であり、event.locationから実カーソル移動を推定しない。[Hammerspoon実装](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap_event.m)はapp指定でPostToPSN、指定なしでsession Postを選ぶ例だが、postToPidや本VMの成功証拠ではない。

ホストの非GUI検証と媒体準備までを行い、guest導入・実行は完成成果物のハッシュを確認して別途判断する。権限不足なら変更せず停止。承認後の入口は `bash /Volumes/Tabbed-Guest-Harness/TEST.SH run plain-click --confirm-isolated-guest`。旧0.6媒体・ログ・guest状態を保全し、今回guest操作は行わない。

## 0.6の最小修正とguest結果

**最新の対照試験:** 同一0.6の入力なし診断を1回起動し、最新画面で特定した青い空白領域へCUA clickを1回行った。run `AF77DC2E-08EB-4168-90FB-13029A19212B` のinput.jsonにwindow422・tag0・Command=falseのdown→drag→upが記録され、共通NSWindow handlerとファイル出力の動作を確認した。FixtureはprocessProbe=falseであり、process専用gate・合成CGEvent・修飾入力・Tabbedの成功とはしない。AX hitも同runのFixture Aを示した。[対照結果・終了状態](docs/build-result-20261021.md)。

**合成入力の結果（同一0.6の再登録後）:** 再登録と再開への個別承認後、guest設定UIでHarnessだけを再登録。run `F242FBEF-FD55-46FD-A7F1-A148A5E33FEA` はevent-post preflightを通過し、Fixture起動・processProbe=trueのhandshake・通常クリックのPID宛て送信とソフト上の解放処理を通過したが、input.jsonがなく停止した。合成入力のNSWindow受信成功は未確認。最初の失敗で止める条件に従い、⌘クリック/ドラッグ、再送、修正、新版作成は行わなかった。専用アプリは正常終了済みで、実行処理・認証/承認待ちは残っていない。[詳細記録](docs/build-result-20261021.md)。

2026-10-21、最終ISOに対する導入・3probe各1回の明示承認後、既存権限のまま通常クリックから開始した。run `26D2E7F3-D150-43EA-A982-DB5DB8702DB0` は `Guest event-post permission missing. No request or setting change was made.` で停止。Fixture起動・入力送信前であり、受信ログはない。最初の失敗/権限不足で停止する条件に従い、Command click/drag、再試行、権限再設定は行わなかった。0.6の受信側修正を実OSで確認できた結果ではない。[停止結果と保全状態](docs/build-result-20261021.md)を参照。

段階2のprocess probeだけは、他プロセスのCG矩形を実際のhit領域とみなす判定を使わない。送信は従来どおり `CGEvent.postToPid` で固定内包FixtureのPID宛てに限定し、sessionへのfallbackはない。署名/hash、run ID/PID/窓ID、前面アプリ、CGの対象矩形内・on-screen、空白領域、入力直前の画面/scale確認は維持する。Dock名やlayer番号を除外条件へ追加しない。旧session smoke/E2EのtopWindowとAX hit条件は変更しない。

Fixtureをprocess probe専用モードで起動し、handshakeで同モードを照合する。FixtureのNSWindow.sendEvent入口では、mouse down/drag/upについてtag・Aの窓ID・現在のNSView空白boundsの12pt内側・NSView.hitTestの結果を確認し、失敗した入力は標準AppKit処理へ渡さず `rejected-*` として記録する。tagが失われた入力や、process probe中の手動マウス操作もFixture内では拒否する。Fixtureの終了にはHarnessの専用Closeボタンを使う。flagsChangedは従来どおり記録し、Command releaseが既知Fixtureで観測できなければ成功にしない。

これはOSがイベントを配送する保証ではない。NSWindow入口で正しい窓・実座標・tag付きの受信を観測し、既存の厳密な列/修飾/release判定が通った場合だけprocess transportのPASSとする。受信したcontent座標・bounds・blankHitも同じinput.jsonの各行に残し、拒否時の観測不足を避ける。NSView内のボタン操作やsession tap/Tabbed受理を確認したことにはしない。AX許可は使わず、event-post preflightだけを使う。新たな権限変更は行わない。0.5のAX_NOT_TRUSTEDが署名変更で生じたかは未確定のまま。

API確認: [CGEvent.postToPid](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)) とSDK26.5のCGEvent.h、[NSView.hitTest](https://developer.apple.com/documentation/appkit/nsview/hittest(_:))。hitTestにはsuperview座標を渡し、boundsの確認にはcontent view座標を渡す。これらのローカルhit確認は他アプリを含む画面全体のmouse hitを判定しない。

非GUI検証は98 assertions・媒体判定25ケース・型検査/ビルド・署名・ISO往復が成功。最終出力は `exports/20261021T050857Z`（[ハッシュ](docs/build-result-20261021.md)）。初回のevent-post falseは、同版の許可再登録後には通過した。ただし実受信は確認できず、後続probeや本体E2Eへ進めていない。署名変更が最初の権限問題の原因か、今回どの段階でイベントが届かなかったかは未確定。

## 入力なしの地点診断（2026-10-21実施済み）

対象ハッシュへの明示承認後、既存権限のまま `diagnose-point` を1回実行した。run `F2051D56-FF31-45BC-A0B8-7FAA4F2021DA`、結果は `DIAGNOSTIC_ONLY_NO_INPUT`。予定点(210,618)のCG候補は返却index6のDock（PID1744/window267、layer20、alpha1、bounds=(0,0,1869,882)）、次がindex8のFixture A（PID2871/window365、layer0、bounds=(30,467,360,270)）。0.4の判定はDockを採用してREJECT_UNEXPECTED_FOREGROUNDとなった。AX hitはAX_NOT_TRUSTED_NO_REQUESTで取得せず、許可の再設定もしていない。[詳細・保全ログ・残存状態](docs/build-result-20261021.md)を参照。

直後のCUA画像では予定点が青いFixture A内部にあり、Harnessの矩形は重なっていなかった。CG上の全画面Dock矩形を、実際に入力を遮る領域と同一視できるかは未確認。前回0.4には候補IDの記録がないため、今回の再現結果を前回の完全な事後証明とはしない。入力配送、AX hit、Tabbed受理、段階3はいずれも未確認のまま。原因確認としての診断はここで止め、一律Dock除外や入力APIの先回り置換は行わない。

0.4の停止原因を確定するため、`diagnose-point` を追加した。内包Fixtureを同じ順序・位置で表示し、activate後0.4秒でAの空白領域中央を計算する。前回の予定点(210,618)は比較用に記録し、hostの画面座標をguest入力座標に流用しない。

`point-diagnostic.json` に、地点・初期/CG矩形・座標系/scale、前面PIDの前後、地点を含むCG行の返却順とID/PID/ownerName/layer/alpha/bounds、0.4のフィルターが採用する最初の行、AX hitのPID/role/窓を記録する。他アプリの窓タイトルや文書本文は収集しない。AX許可が不足していれば要求せず、その状態を記録する。観測は時刻で挟んだ順次取得で、CGとAXが原子的に同時の情報であるとは主張しない。

このシナリオはInputLease・イベント生成/送信・Tabbed起動の前で終了し、結果は `DIAGNOSTIC_ONLY_NO_INPUT`。PASSや配送成功にしない。診断起動したUIではsmoke/E2E開始ボタンを無効化する。既存topWindow判定と許容幅、通常probeは変更しない。アプリ自身は画面撮影も権限要求もしない。実行承認後は窓を保持した状態で既存CUAの画面を直ちに取得して照合するが、JSON取得とスクリーンショットを同時刻とは扱わない。

```sh
# 対象0.5媒体の導入・実行承認後のみ。観測1回、入力送信なし。
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run diagnose-point --confirm-isolated-guest
```

今回の0.5は対象ISOのハッシュを示して別途確認を受けて実行した。新しい権限変更は行わず、必要なら別途対象を確認する。新しいバイナリの実行を包括承認されたものとは扱わない。通常入力試験や段階3へは進めていない。

## 現在の段階計画

全体の計画と入口は[リポジトリREADME](../../README.md)の `bash Tests/test.sh`。内部回帰は既存7件＋本体メソッドを使う11件が通過した。実AX・NSApplication・実操作を確認した結果とは区別する。

段階2は0.4の `plain-click` → `command-click` → `command-drag` を**別々のrun**で確認する。正しいFixture窓のtag付き受信、修飾の有無とrelease記録を合格条件とし、失敗した段階で止める。2026-10-21、対象限定承認後に0.4を導入・検証し、guestのHarness権限を再登録した。初回plain-click（run `66EF834F-C158-4980-88C0-AACAC4D06239`）は前面ウィンドウ判定で入力生成前に停止。受信は未確認、残る2probeは未実行。再試行・修正・次版作成は行わず終了した。[実測結果と残存状態](docs/build-result-20261021.md#追記-04のguest導入と初回plain-click結果2026-10-21)を参照。

個別probeは `CGEvent.postToPid` でLaunch Servicesから得た内包FixtureのPIDにだけ送る。0.4のCG最前面確認は0.5診断でDockの全画面boundsを拾うことが分かり、0.6のprocess probeでは上記の受信側確認に置き換えた。AXへのアクセスやAX/CG全体矩形一致を入力条件にしない。必要なguest権限はevent-postのみをpreflightする。追加要求が出たら停止する。署名・PID・window ID・前面・on-screen・1画面/VM確認、Stop/タイムアウトのreleaseは維持する。

**process宛て配送の成功は、session tapへの配送やTabbed受理を証明しない。** 段階3ではこの差を明示してsession経路を含む実操作を確認する。既存のsmoke/E2E経路は保全しているが、今回の段階2の実行対象に含めない。0.4にも旧Tabbedハッシュが残るが、段階1のprune修正はその旧バイナリに含まれないため、段階3前に本体を改めてbuild・検証し、対象ハッシュを更新する必要がある。

承認後にguest内で使う単独入口は次のとおり。各run完了後、既知のFixtureを専用Closeボタンで閉じてHarnessを通常終了してから次へ進む。Fixtureが残ったまま自動再試行しない。全段階を連続実行する自動cleanupはまだ実装せず、最終的な単独実行の目標と区別する。

```sh
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run plain-click --confirm-isolated-guest
# 上記の受信確認・専用アプリ終了後に限り:
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run command-click --confirm-isolated-guest
# 上記の受信確認・専用アプリ終了後に限り:
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run command-drag --confirm-isolated-guest
```

結果modeは `PROCESS_INPUT_PROBE_<scenario>`。clickはdown→up、dragはdown→drag→up、Command付きはその後のflags/Command=falseまで同じFixtureの受信記録で確認する。最終CGフレームは記録するが、AX/CG全矩形一致によって受信成功を否定しない。未知の対象への入力・global/session経路への自動fallbackは設けない。

隔離した Apple Silicon macOS VM 内で、専用ウィンドウへの入力配送と Tabbed の通常 Quit を調べる。ホストではアプリを起動しない。Xcode は不要。ホストの Command Line Tools でビルドし、同じ `test.sh` を入口に準備とゲスト実行を分ける。

ゲスト smoke は0.1が座標照合、0.2診断版も権限再登録後に座標照合で停止した。0.2のAX/event-post事前検査は通過した。[0.2実測記録](docs/guest-smoke-v02-result-20261021.md)は当時のprepare不具合も含む履歴で、0.4のprepareはguestで成功した。入力受信の成功は依然未確認。初回ログイン、権限許可、媒体接続は人による準備が必要で、VM構築からの全自動化は未実装。スクリプトはsmokeと3種のprocess probeに対応する。E2Eは未実行で、別途承認後のUI開始に限る。

0.3ではFixtureの自動表示アニメーション抑制、起動/activation後の複数回安定観測、空白コンテンツへの入力限定、CGの最前面IDとsystem-wide AX hit照合を追加した。許容差3ポイントは拡大しない。prepareのキー参照も修正。[調査・修正方針](docs/geometry-investigation-20261021.md)を参照。**0.3のゲスト導入・実行と権限変更は未承認・未実施**であり、0.2の実行承認を流用しない。

## 配置と移行

既存の `Tests/` 配下の `Tests/guest-e2e` に置く。`project.yml` の `TabbedTests` は `guest-e2e/**` を除外し、専用アプリ・Fixture・独立ポリシーテストをXCTestへ混入させない。`Sources/Driver` は操作と観測、`Sources/Fixture` は試験ウィンドウ2枚、`Sources/Shared` と `Tests` は純粋ポリシー試験。`scripts` はビルド・署名コピー・媒体作成を担う。

リポジトリと同階層の旧 `tabbed-guest-harness` の実装をここへ移し、旧位置には移行案内とソースへの symlink を残した。旧 exports・署名済み ISO/ZIP・ログは保全する。移行前ハッシュは `docs/migration-source-hashes.json`。新出力 `exports/` とキャッシュ、資格情報、VM、バイナリ、結果、個人設定は git へ追加しない。資格情報を引数やログで受け取る機能はない。

## ホストでビルド・媒体作成

リポジトリルートで実行する。

```sh
./Tests/guest-e2e/test.sh help
./Tests/guest-e2e/test.sh host
# 個別実行の場合
./Tests/guest-e2e/test.sh build
./Tests/guest-e2e/test.sh package exports/<表示されたUTC時刻>
```

SDK の固定パスは `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`、arm64 / deployment target macOS 14.0。Python 3 と macOS 標準ツールを使う。今回の0.1/0.2導入では macOS 26.6.2（25G83）と VM flag=1 を確認した。0.2は起動して権限事前検査の結果を保存できたが、入力受信の互換性は未確認。

`host` は型検査、2アプリの build、純粋ポリシー98 assertionsとshell媒体判定25ケース、コピーの ad-hoc 署名、ZIP と HFS+/ISO9660 raw ISO 作成、実 ISO→ZIP→展開後の全パス・バイト・モード・署名の照合まで行う。ホストで実行するテストはSharedとTestsの純粋ポリシーおよびshell判定だけで、AppKit/AX/イベント送信を実行しない。アプリや VM は起動しない。Swiftキャッシュはビルド出力ごとに分離し、配置移動前のキャッシュと衝突させない。

毎回新規 `exports/<UTC>/` へ出力し、包装済み出力への再実行は停止する。`artifact-sha256.json`、`media-sha256.txt`、`commands.json`、`packaging-commands.json`、各ログを保存する。ISO 内は `HARNESS.ZIP`、`SOURCE.ZIP`、`BUNDLE.SHA`、`SHA256SUMS`、`README.TXT`、`TEST.SH`。ISO 原本は0444。UTM の Read Only は別途必要。

アドホック署名は改変検知であり、配布者の認証や安全性の保証ではない。実行は確認・承認したハッシュの成果物に限定する。版が変わると新たに確認する。過去の既承認0.1 ISO は旧出力 `20261021T015525Z`、SHA256 `afd9af0f8cbf8252c572328e7568b736ba6852af2314ebfc7bbc539a2a50d8eb`。旧媒体には TEST.SH はなく、UI での smoke 開始を使う。0.2の実測は上記記録を参照。

## VM を準備する（人による初回設定）

1. UTM の Apple Virtualization で専用 macOS VM `Tabbed-Test` を作成する。macOS 14以上の arm64 がビルド上の要件だが、実ゲスト互換性は未確認。1画面、表示可能領域1100×700ポイント以上を使う。
2. 試験専用の guest アカウント（現在は `test`）をユーザーが作成・ログインする。パスワードをソース、引数、チャット、ログへ書かない。本スクリプトはアカウント・パスワード・ログインを自動化しない。
3. 初期設定後は完全シャットダウンし、ネットワークアダプター削除、共有フォルダなし、クリップボード共有オフで設定を保存する。停止した VM を UTM の「複製」で `Tabbed-Test-clean` として保全する。clean と試験 VM を同時起動しない。通常試験で clean を編集しない。
4. **試験ゲスト内だけ**で自動ロックを解除する。ユーザーが「システム設定→ロック画面」でディスプレイオフを「しない」、スクリーンセーバー開始／ディスプレイオフ後のパスワード要求を「しない」に設定し、スクリーンセーバーによる中断も避ける。項目名は OS により異なる。ホストには適用しない。今回ユーザーが手動設定済みと報告し、guest 画面でも上記2項目を確認した。VM を放置せず、試験終了後は停止または設定を戻す。
5. `sw_vers` で guest OS、`sysctl -n kern.hv_vmm_present` で VM flag を記録する。flag=1 以外は停止し、override を設けない。これは隔離を証明する機構ではない。

## 読み取り専用媒体を接続・検証する

UTM [Apple Drive 文書](https://docs.getutm.app/settings-apple/drive/)と [v5.0.8 実装](https://github.com/utmapp/UTM/blob/v5.0.8/Configuration/UTMAppleConfigurationDrive.swift)を参照。非圧縮 raw イメージを Removable / Read Only で使う。停止中の試験 VM にドライブを追加する場合はシステムディスクより後ろに置く。

UTM マネージャで対象名 `Tabbed-Test` を確認し、外部ドライブ→選択で検証済み ISO を選ぶ。停止が必要なときは guest 内の未保存書類を保存して通常シャットダウンする。強制停止や書類破棄はしない。ネットワーク・共有は無効のままにする。

2026-10-21 の稼働中媒体交換では UTM が「ファイルを開けませんでした」と返し、元の媒体名を表示した。その後guest側で媒体が認識され、Media/Volume Read-Only=Yes、承認済みZIPのSHA256、媒体マニフェストと展開後全bundle hash・strict署名が一致した。マネージャ表示と実際の接続が食い違うため、guestでの確認を必須とする。エラー時に権限や Read Only を緩めたり、原本の属性を変更したりしない。

ホストで ISO 自体の SHA256 を確認後、guest Terminal で実際の volume 名を確認する。以下は0.3媒体の手順で、導入・実行前にその成果物の承認が必要。

```sh
cd /Volumes/Tabbed-Guest-Harness
shasum -a 256 -c SHA256SUMS
bash TEST.SH prepare /Volumes/Tabbed-Guest-Harness
bash TEST.SH verify
```

`prepare` はguest判定・diskutilのWritableVolume/WritableMediaが両方false・媒体ハッシュを確認し、固定新規 `~/Tabbed-Guest-Harness-Test` へditto展開、全bundle hash、内包FixtureとHarnessのstrict codesignを確認する。未知値・欠落は停止。0.2のキー参照誤りは0.3で修正したが、修正版prepareのゲスト実証はまだ行っていない。既存ディレクトリは上書きしない。アプリとFixtureを通常終了して旧版と結果を別名で保全し、新しい固定フォルダを用いる。失敗した部分展開も保全する。署名再作成・quarantine一括除去・TCC編集をしない。

## ゲスト権限と開始

Harness の固定導入先を確認し、guest の「プライバシーとセキュリティ→アクセシビリティ」で **Tabbed Guest Harness.app のみ**に許可する。AX と event-post が必要で、アプリは `AXIsProcessTrusted` / `CGPreflightPostEventAccess` を読み、足りなければ停止する。Fixture に追加権限は不要。Input Monitoring、画面収録、Full Disk Access、Apple Events Automation は前提にしない。追加要求・予期しないセキュリティ警告が出たら停止して判断する。ゲストの認証が必要な場合はユーザーが入力する。

まず既存 Tabbed を通常 Quit し、他作業を終える。未保存書類は保存してから行う。Harness は既存 Tabbed/Fixture、複数 Harness、想定外の画面・被覆などで停止する。

通常起動は手動開始 UI だけで、自動入力しない。

```sh
bash /Volumes/Tabbed-Guest-Harness/TEST.SH open
```

チェックボックスを確認し「1. Start transport smoke」で開始する。スクリプト実行を承認した版では、代わりに次の1コマンドを使う。

```sh
bash /Volumes/Tabbed-Guest-Harness/TEST.SH run smoke --confirm-isolated-guest
```

このコマンド自体が明示開始となり、画面に環境・対象を表示後、権限などの preflight を経て smoke を開始する。厳密な引数列以外は実行しない。E2E を引数で開始する機能はない。手動用 Harness が起動中なら先に通常 Quit する。

smoke は固有UUID/PID/AX識別子/WindowServer IDで照合した試験ウィンドウ2枚を生成し、一方の空白上に⌘付き短距離ドラッグを送る。tag、対象ID、down→drag→up、Command、移動していないこと、終了後の左ボタン/Command解放を確認する。**Tabbed のグループ化を確認する試験ではない。** 旧0.1のゲスト初回実測は AX / WindowServer geometry disagreement で入力前に停止した。結果は [guest-smoke-result-20261021.md](docs/guest-smoke-result-20261021.md)。

入力中は人がキーボードやポインターを操作しない。停止が必要なら Harness の STOP を押す。送信終了・例外・Stop・3秒 watchdog で事前確保した解放イベントを送り、以後の送信を止める。OS停止・プロセス強制終了・権限失効時の配送は保証できない。

## 判定・結果回収・復旧

試行は75秒の協調的期限、起動応答待ちは10秒。スクリプトは最大90秒待ち、新規UUIDの `result.json` の runID/mode/result が一致し PASS のときだけ exit 0。前回の結果、UIを開けたこと、timeoutを成功に数えない。起動を OS へ依頼した後の timeout では遅れて起動することがある。自動再試行・killはしない。

結果は guest の `~/Library/Application Support/TabbedGuestHarness/<UUID>/`。`result.json`、`driver.jsonl`、`fixture.json`、`input.json` に結果・試験対象の固定情報・イベント metadata を記録する。入力文字や資格情報、他アプリのタイトルは記録しない。

```sh
bash /Volumes/Tabbed-Guest-Harness/TEST.SH results <表示されたUUID>
```

画面の結果とUUIDを記録できる。読み取り専用ISOへは書き戻せない。完全ログ回収用の専用出力ディスクやQR出力は未実装・未検証で、別途設計・承認が必要。回収のために network/share/clipboard を有効にしない。失敗時は画面とログを残し、今回の試験ウィンドウは Harness の「Close this run's test windows」で閉じる。これはこの run の既知 Fixture に限る。Stop はグループ化を巻き戻さない。

復旧は未保存データと必要な結果を保存して通常シャットダウンし、clean から新しい作業用複製を作る。既存 VM や clean を上書き・削除しない。権限を戻す場合は guest の Harness 項目だけをユーザーが確認して変更する。

## 次段階と未確認事項

E2E の UI ボタンは固定 `~/Tabbed-Quit-Fix-Test/Tabbed Quit Fix.app`（bundle ID `dev.local.TabbedReviewed`、実行ファイルSHA256 `e243618224ad8ecb90437de4848e596b571a31d5e4d6cc40ffba9a989e2cf073`）を新規起動する。対象 drag tap の有効化を観測し、実際にAがB位置、Bが画面外へ退避したことを観測後、AXの `Quit Tabbed` から通常終了する。元の2枚の生存、同一画面内フレーム、非最小化、on-screenを3回確認する。未承認・未実施。kill や直接内部関数呼び出しへの代替はない。

合成入力のOS配送・Tabbed受理、AX識別子公開、VM flag、guest OS互換性、AXメニュー、実際の選択状態は静的レビューで保証しない。通常Quit成功でも一時AXエラーで管理対象から落ちる問題の検証にはならない。fault injection、複数組/複数画面/Spaces、物理入力、クラッシュ復旧は未実装。保証範囲と次の試験案は [test-scope.md](docs/test-scope.md)、レビューは [review.md](docs/review.md)。

0.3では起動/activation後それぞれ最大4秒で3回・0.3秒以上の安定を要求する。各回は同じPID/ID/identifier/title/roleを検証し、AX/CG一致は従来の3ポイント、時間的な変化は最初のサンプルから0.5ポイント以内とする。raw sampleはdriver.jsonlへ保存する。入力保持中の収束待ちはせず不一致で解放・停止する。空白コンテンツ領域とAX hitが確認できない場合も停止するため、E2Eのdrop indicatorでAX hitが別対象を返す可能性は未解決の実証項目。

## Tests 配下への配置整理（2026-10-21）

`tools/guest-e2e` から `Tests/guest-e2e` へ移動した。旧tools位置には互換symlinkだけを残し、既存成果物へのリンクを維持する。旧単独ディレクトリのSources/Tests/scriptsの互換symlinkも新しい正本へ向け直した。過去のexports内のsource snapshot、署名済みapp、ISO/ZIP、コマンド・実測ログは書き換えず保存し、そこに残る旧パスは当時の記録として扱う。今後の入口はリポジトリルートから `./Tests/guest-e2e/test.sh`。`test.sh` は自身の物理ディレクトリ、build/packageはスクリプトの実体からrootを決めるため、移動後も同じ相対構成で動く。配置整理でアプリのソースと実行バイナリは変更せず、build・XCTest・guest試験は実行していない。
