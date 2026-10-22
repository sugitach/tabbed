# Test scope and safety boundaries

最新run `AE049562-C67F-4431-809E-B26CBED2FB4E` は、承認されたauto-add OFF後の同一0.11の1回。group入力の送信とCommand解放受信後、OSの押下状態検査で停止。baselineの3チェックポイントのみ確定し、group結果の自動検証/解除/regroup/Quit/復元は未完了。送信成功・Fixture受信・OS全体状態を区別し、残留した具体的なmodifier/buttonと原因は未確定。最初の失敗後はログ読取りのみ、アプリ3個と窓を保全。[記録](build-result-20261021.md#011-auto-add-off後の再実行group後の解放状態検査で停止)。以下は準備と過去の履歴。

最新実測では、承認された同一0.11のguest導入/検証と同2appのAX再登録が完了。初回 `run e2e` はauto-add保存設定ONを検出してpreflightで停止。Harnessの権限/署名/hash検査後、Fixture/Tabbed起動や入力前の停止で、group/解除/regroup/Quitは未実施。再試行や設定変更なし。[停止記録](build-result-20261021.md#011-guest導入許可更新と初回preflight停止)。以下のguest承認待ち・未導入は準備時点の履歴。

最新の準備は0.11。実証済みsession入力を使った単独E2E（group→drag-out解除→regroup→通常Quit）を実装し、176 pure assertions・媒体25ケース・最新本体を含む3app型検査/build/署名/実ISO往復が成功。本体ソースは不変。最終ISO SHA256 `e06a4a04ccb046d4ffa5980b409fcfd4e24bb10e93a135e29d6cdc36fca31335`。guest実行/導入/許可更新は承認待ちで未実施。[成果物と具体的範囲](build-result-20261021.md#011最終成果物と実行承認待ち)。

入力点は現在のAのAX blank content・CG ID/owner/frame・実AX hitで確認し、動くAの内側へ100pt以下で分割する。DockのCG bounds除外、全AX/CG一致や許容幅の増加、擬似handler呼出しは使わない。group/解除は窓状態と本体所有stripの出現/消失、Quitは同じ2枚の共通frame復元と非最小化/on-screen、target終了/tap消失、専用アプリcleanupで判定する。失敗時は解放して証拠と窓を保持、再送/修復/強制終了なし。xのuntab-offset経路、AX故障注入、異常終了/watchdogの実OS配送、物理/hostからの修飾転送は未検証。以下は過去の準備と実測。

段階3の準備では、同じFixture2枚をグループ化→解除→再グループ化→通常Quitの順で確認する仕様と停止条件を整理した。[詳細と未実装点](../README.md)。本体コードを変えず、既存署名/hash・shell構文のみ確認し、新build/実行/guest操作は行っていない。現0.10のUI E2Eは旧guard/旧targetのままで今回の全シナリオを実装していないため、実行準備完了と扱わない。

最新実測では、同一導入済み0.10の `SESSION_INPUT_PROBE_command-click` と `SESSION_INPUT_PROBE_command-drag` が各1回PASS。ユーザー本人の直接確認後、前者の成功確認・正常終了を挟んで後者を実行した。受信tag/窓ID/順序/時刻/raw flags/座標と解放、結果保存を確認。専用アプリの残存なし、追加権限変更なし。[実測記録](build-result-20261021.md#追記-010のcommand-clickとcommand-drag成功)。

段階2の単純クリック（0.9）と修飾クリック・ドラッグ（0.10）の受信確認は完了。これは今回の専用Fixture・VM・画面条件での成功であり、Tabbedの監視・グループ化・解除・Quit復元、実キーボード/VM転送、watchdog障害時の実OS配送を保証しない。段階3は未実施。以下の承認待ち・未実行は準備時点の履歴。

現在は0.10のguest導入・署名検証・同Harness許可再登録まで完了。Command-click起動のGUI操作は直接ユーザー確認の認識不足を理由に自動承認審査で拒否された。入力/試験は未実行、再試行なし。以下のguest未導入などの記述は準備時点の履歴。[現在の状態](../README.md)。

ホストの0.10検証は純粋143 assertions・媒体25ケース・型検査/build/署名/ISO往復が成功。Command操作はguest未実施、具体的な実行時承認待ち。[選定成果物と手順](../README.md)。以下の設計や履歴から実OS成功を推定しない。

## 次段階: 0.10のCommand操作を準備（guest未実行）

通常session clickの実受信成功を踏まえ、0.10は `command-click` / `command-drag` も同じsession経路にそろえる。今回の準備はホストでの実装・非GUI検証・署名媒体作成まで。0.9の通常click1回の承認は、新版やCommand操作には拡張しない。次の具体的対象は完成した同一0.10の導入・必要な同Harnessだけのguest AX/event-post再登録・Command-click1回、成功した場合だけCommand-drag1回。最初の失敗で止め、再送・本体E2Eへ進まない。

各試験は専用Fixtureを前面にし、署名/hash/run ID/PID/window ID・画面/scale・AX hit・現在の空白領域/CG枠内を送信前に検査する。通常clickと同じ安全確認を、⌘押下前・mouseDown前・drag前・mouseUp前・⌘解放前に行う。session入力はPIDに限定されず、確認後に対象が変わる競合が残るため、実行中はguestで他作業をしない。既存の3秒watchdogとrun全体75秒制限を維持する。停止時は実際に押下を試みた分だけを解放し、mouseUp後の待機中ならCommandUpだけを送る。プロセス/OS停止・権限失効時の配送自体は保証できない。

順序は⌘押下→0.12秒待機→mouseDown→0.12秒待機→（dragなら同じ空白view内を右へ30pt移動し0.12秒待機）→mouseUp→0.12秒待機→⌘解放→0.3秒待機。追加文字キー、cursor warp、受信handlerの直接呼出しは加えない。

合格にはtag付きのflags(Command=true)→down→（drag）→up→flags(Command=false)の厳密な列と時刻順序が必要。マウスは同一A、flagsは同じrunのFixture A/Bだけを許可する。Commandのboolとraw flagsを照合し、Shift/Control/Optionの混入、押下/解放欠落や順序不正を失敗にする。受信content座標はclickが同一点、dragが予定の30pt移動と終点upを0.5pt以内で示し、blankHit=true、受信ログの書込み完了まで要求する。raw flagsはinput.jsonへ追加し、DeliveryTraceにも従来どおり記録する。結果modeは `SESSION_INPUT_PROBE_command-click` / `SESSION_INPUT_PROBE_command-drag`。

詳細な入口と履歴は[README](../README.md)。以下は過去の記録。

## 最新結果: 0.9のsession通常clickが成功（2026-10-21）

ユーザー本人の、このチャットでの具体的な文字による実行承認後、同一導入済み0.9を1回だけ実行した。run `099BBB80-EA09-42B3-A335-FE9E0F45B75D`、mode `SESSION_INPUT_PROBE_plain-click`、結果 `PASS`。権限preflightと送信前AX hit確認を通過し、Fixture PID5223のA/window564にtag付きdown/upが各1件届いた。両方Command=false、content(180,119)、blankHit=true。local monitorとNSWindow入口のwindowNumber/windowは564で、受信gateのaccepted=trueとinput-write-okのreceiptCount=2を確認した。通常session経路で専用Fixtureがこのクリックを受信・保存したことが今回の確認範囲である。

FixtureとHarnessを通常終了後、guestのpgrepでHarness/Fixture/Tabbed一致なし。未保存TextEdit、旧成果物/ログ、隔離を保持。ログはguestの `~/Library/Application Support/TabbedGuestHarness/099BBB80-EA09-42B3-A335-FE9E0F45B75D/` に保存。⌘操作とTabbed本体E2Eは未実施。[受信根拠・ハッシュ・終了状態](build-result-20261021.md#追記-09のsession通常click成功)。以下の停止記録とguest未実行の記述は、このrun以前の履歴として残す。

## 現在の準備（0.9、guest未実行）

plain-clickのみ通常session配送へ変更。guest AX + event-postをpreflightし、同一Fixture PID/windowをAX identifierとsystem-wide point hitで確認する。点は現在のAX contentとCG ID/owner/bounds内、対象は前面かつon-screenであることを送信前に確認する。AX/CG全矩形の厳密一致、他プロセスのCG boundsをhit領域とみなす判定には依存しない。sessionはPID限定ではなく確認後の競合が残るため、他作業をしない隔離guestで1回に限る。

Fixture gate/ログは0.8のまま。直接handler呼出し、未知field、mouseMoved/warp、再送は加えない。成功条件は実際のtag付きdown/upが同一AのNSWindow→受信gate→receipt/trace書込に到達すること。結果modeは `SESSION_INPUT_PROBE_plain-click`。修飾入力とTabbed E2Eは未実施で、次の対象にも含めない。新成果物の導入/必要な同Harness guest権限再登録/1 runは具体的な成果物を示して判断する。以下は履歴。

## 最新の実測（0.8、公開2fieldだけではwindow未割当）

同一0.8の導入・必要なguest同Harness再登録・通常click 1回の承認後に実行。preflight通過。送信したtag付きdown/upはAppKit local monitorへ到達し、指定したwindow fields91/92=期待するAのIDも保持されたが、NSEventのwindowNumber=0/window=nilのままで、mouse eventのNSWindow入口/gate/出力は未確認。結果はinput.json不在のSTOP_OR_FAIL。2fieldだけで十分という仮説はこの実行条件で支持されなかった。

停止条件に従って再送/追加field/別経路/新版へ進まず終了した。専用アプリの残存なし、ログと隔離保持。通常のsession入力を採用するかは安全条件を含めた次の設計判断であり、今回の範囲では行わない。processのAppKit到達をwindow受信やsession/Tabbed成功と扱わない。以下は準備時点と過去の記録。

## 現在の準備（0.8、guest未実行）

0.7のAppKit到達/window未割当を受け、process probeのmouse eventだけに公開field91/92へ検証済みAのIDを設定する。固定PID・同一window ID・安全領域を維持し、正のPIDと非ゼロIDがそろわなければ生成前に停止。session fallbackやFixture内での直接呼出しはない。旧session/E2Eではfieldを設定しない。watchdog/通常upにも同じ窓情報を付ける。

公開fieldの指定でこのOSがwindowを割り当てるかは未実証。既存実装のmouseMoved/clickCount等を同時に取り込まず、一つの仮説に絞る。次の具体承認は0.8の導入・必要なら同Harnessのguest許可再登録・plain-click 1回をまとめた範囲。window=0/nilが続けば追加fieldの反復を止め、通常のsession配送と安全条件の設計を再評価する。fixture内で強制的に成功させない。詳細・一次資料は[README](../README.md)。

## 最新の実測（0.7再登録後、AppKit到達・window未割当）

個別承認後に同一0.7のHarnessだけをguest正規UIで再登録。1回のplain-clickはpreflightを通り、tag付きdown/upがFixtureのlocal monitorで観測された。両方windowNumber=0/window=nilで、期待するAのNSWindow入口には到達記録がない。gateとinput.json書込みは実行確認できず、結果はSTOP_OR_FAILのまま。新たな実証はprocessのAppKit dispatchまでであり、window受信・通常clickのPASS・session配送・修飾入力・Tabbed受理ではない。再送・変更版・本体試験は行わず、専用アプリを正常終了した。下記は過去の段階と設計の記録。

## 直前の実測（0.7、入力前停止）

対象ISOの導入と既存権限でのplain-click 1 runへの承認後、0.7を検証・導入して開始した。run `6A1BB027-42F8-427C-A53B-6BD9E92A2418` はevent-post preflightで停止し、FixtureやInputLeaseへ到達していない。権限変更・再送・別probeは行わず、Harnessを通常終了した。通常入力対照以降の配送境界の観測は増えていない。以下の試験案は準備時点の設計として保持する。

## 限定試験案（0.7の設計）

次の実行案はprocess専用modeのplain-click 1 runのみ。生成・配送API・gate・waitは0.6のまま、送信CGEventのraw fields、実カーソルの前後位置、自アプリlocal monitor、window入口、gate判定、encode/write完了を記録する。[READMEの判別手順](../README.md)を参照。local monitorで見えないことをOS配送失敗とは断定しない。通常modeのCUA対照成功を専用modeの出力成功と扱わない。

診断ログは最大128行のmetadataで、Fixture自身のprocess probeに限定する。global tap、入力監視・画面収録の追加権限、session fallback、cursor warp、window field書換えは加えない。送信ログのI/Oはlease解放後に行う。handshakeとreceipt書込完了を確認できなければPASSにしない。実際の入力先が正しいこと、tag・修飾の保持はguest実測まで未確認。ホストの型/ビルド/署名/媒体検証だけでは証明しない。

完成成果物による1 runの実行と、必要ならその後の権限変更は別の対象として判断する。今回はguest操作・本体E2E・再送を実施しない。以下の版ごとの記述は履歴として保持する。

## 見直し後の現在位置（0.4）

段階1の内部回帰は `bash Tests/test.sh` で実施済み。詳細は[本体の検証記録](../../../docs/build-validation.md)。実AXではなく、選択した実際の本体メソッドに模擬AX/UI境界を与える試験であり、既存7件と新11件が成功した。

段階2として0.4はplain-click / command-click / command-dragの個別process probeを実装した。Launch Servicesから取得し署名/hashを確認したFixtureのPIDだけへCGEvent.postToPidで送り、正しいwindowID・tag・modifier・releaseの受信を判定する。AXは使用せず、入力点がFixtureの空白コンテンツとCGの最前面の同じwindowID/ownerPIDに属することを確認する。全矩形一致は入力条件にしない。global/session経路へfallbackしない。

これはsession tapを通ることやTabbed受理の実証にはならない。CoreGraphicsのSDK26.5 CGEvent.hはprocess宛てpostingを定義しており、session tap配送の保証としては扱わない。下記の従来smoke/E2Eとは結果modeを分ける。個別probeの実guest受信は未承認・未実施で、最初はplain-clickを1回。失敗したらその段階で停止し、既知の同じ不一致に対する微調整は続けない。下記の将来案は段階1で実施済みとなった箇所を含む履歴として読む。

## この版に実装した段階

1. Pure policy: 入力receipt順序・tag/ID/Command判定の負例、画面内復帰の境界、UUID制約。ホストで実行可能。アプリや入力送信コードはリンクしない。
2. Guest transport smoke: Tabbed不在でfixtureがCommand付きdown/drag/upを受け、元のフレームが保たれる。0.2は権限通過後に入力前の座標照合で停止。現在の0.3はguest導入・実行が未承認・未実施。
3. Guest E2E: 未改変の既知Tabbedバイナリを固定パスから新規起動し、CGEvent→session tap→グループ化→実AX/WindowServer観測→AXメニューによる通常Quit→元のwindow IDの生存/復帰を見る。内部formGroupなどを直接呼ばない。どの版でもE2Eは未実施。

同じfixtureプロセスの2枚だけで最小試験を行う。異なるアプリのウィンドウを混ぜる試験、2組以上の試験、ショートカット/全タブ選択、fault injectionは別の段階である。

## 対象誤認の防止

- helperは内包固定パス、署名と実行ファイルハッシュを検証する。run UUIDはcanonical UUIDに限定し、独立の新規runフォルダを作る。
- fixture PIDはLaunch Servicesから受け取り、fixture自身が出すPIDと一致を要求する。AX windowのPID/identifier/title/role/subroleを照合し、登録したwindow IDのWindowServer owner PIDとAX/CGフレームを照合する。
- input開始位置と各drag座標は、そのPIDの登録window IDに属することを確認する。layer=0以外の被さるウィンドウも確認する。
- 0.3はFixtureの自動表示アニメーションを抑制し、同じ対象のAX/CG一致と3回・0.3秒以上の安定を起動/activation後に要求する。許容差を広げない。入力点は実コンテンツの12ポイント内側とCG領域の内側に限定し、system-wide AX hitが同じAX windowであることも確認する。画面構成変更は停止する。
- E2Eドラッグ開始後だけ、検証済みTabbed PIDのstatusBarレベルかつBの初期フレーム+16ポイントと一致するdrop indicatorを除外する。ソースの `DropIndicatorPanel` が `ignoresMouseEvents=true` であることに基づく限定例外。それ以外の被さるウィンドウは停止条件。
- session eventはOSのグローバル座標へ送るため、確認と送信の間のOS競合を完全には排除できない。対象fixtureにフォーカスがあることと直前のocclusionを確認し、ゲスト内で他作業をしない。
- 唯一の非fixture AX actionは、明示E2Eに伴う既知Tabbed PIDのstatus menu/`Quit Tabbed`。他アプリの位置や設定は変更しない。

## 復旧不具合を次に試す方法（未実装）

`AXWindowEngine.isAlive`が一時AXエラーをfalseにし、`pruneDeadWindows`が退避windowを削除する問題は、内部試験と実OS観測を分ける。

1. fake WindowEngineで、閉じていないAの1回だけの生存問い合わせを失敗させる。prune後に成功へ戻し、Quit復元対象にAが残ることを期待する回帰テストを追加する。現行では脱落するはずだが、実行前に成功/失敗を断定しない。
2. AX呼び出し境界を注入可能にし、cannotComplete→unknown、invalidUIElement/process termination→closedなどの判定を別途試験する。
3. 実fixtureを一時無応答にしたゲスト試験はOS挙動の観測になる。ただし `_AXUIElementGetWindow` が狙ったエラーを返す保証はない。観測者のAXエラーとTabbed自身が受けたエラーを混同しない。
4. 必要なら別の診断ビルドでAX戻り値とprune判断を記録し、未改変バイナリのE2E結果と区別する。通常Quitの成功だけをこの不具合の修正確認にしない。

## 権限・実行環境の未確認点

- 過去0.1/0.2ではmacOS26.6.2/25G83、VM flag=1、fixed path、AXIdentifiersと0.2のAX/event-post検査通過を確認した。0.3の新しい安定観測とAX hit、event-source tagの保持、合成Commandの配送、global state readback、status itemのAX公開状態はguestで未検証。
- TabbedのAX権限を別プロセスから確実にpreflightするAPIは使っていない。ユーザーが事前確認し、起動後の有効なdrag tapを読み取り確認する。tap確認失敗時には入力しない。
- watchdogは入力解放の送信試行と以降の送信禁止を実装する。OS/プロセス死亡までの絶対保証はしない。権限を自動取得/再設定しない。
- Source/build/sign/archive検証はGUI描画やE2Eの検証ではない。今回はGUI描画検証・アプリ起動を行わない。

## 0.2 のスクリプト開始

`test.sh` を単一入口にし、host と guest コマンドを分離した。厳密な smoke/execute/guest確認/canonical UUID の引数だけを実行する。通常起動は手動UIのまま。runディレクトリは POSIX mkdir で排他的に作成し、再利用を拒否する。preflight前に新規ログ先を確保するため、権限不足もそのrunの失敗として記録する。GUIアプリや入力送信をhostで実行する検証はしない。初回OS設定とE2E開始の単独スクリプト化は未実装。
# 0.5追加: 入力なしの地点診断

`diagnose-point` は固定内包Fixtureを表示し、0.4と同じ予定点に対するCG候補とAX hitを1回観測する。InputLeaseを生成する分岐へ入らず、Tabbedも起動しない。2026-10-21に対象限定承認後、既存権限で1回実行済み。CG候補のDock採用による拒否を再現し、AXはNOT_TRUSTEDを記録してhitを取得しなかった。権限の要求・設定変更はしない。画面撮影APIを使用せず、新たなScreen Recording権限を必要としない構成。別アプリの窓タイトル・本文は保存しない。CGとAXの観測時刻差はログに残す。`DIAGNOSTIC_ONLY_NO_INPUT` を入力成功やE2E成功と区別する。以下は従来シナリオの範囲を保持した記述。

# 0.6追加: process probeだけの受信側確認

guestの初回実行はevent-post preflightで停止した。その後、同じ0.6のguest許可再登録と再開への個別承認後、preflightを通過し通常クリックを1回PID宛てに送信したが、input.json不在で停止した。以下の受信側処理を実OSで通過したことは未確認。Command click/drag、本体E2Eは未実行。最初の失敗で停止し、同runの再送や新修正はしていない。

別の承認済み対照試験で、0.6入力なし診断のFixtureへCUA clickを1回実施。processProbe=falseの共通NSWindow handlerでtag0/修飾なしのdown→drag→upとinput.json出力を確認した。これは下記process専用gateや合成入力成功の確認ではない。診断のresult=DIAGNOSTIC_ONLY_NO_INPUTはプログラムが合成入力を送らないことを示し、その完了後に別のCUA操作として対照入力を行った。

Dock/layerの除外は追加しない。CGEvent.postToPidだけを使うprocess probeではCGのglobal最前面判定を行わず、固定PID/署名/対象窓/前面/画面と空白領域の確認を維持する。専用Fixtureのモードをhandshakeで照合し、NSWindow入口でtag・Aの窓ID・現在の空白領域・NSView.hitTestを確認、範囲外やtag欠落のmouse入力を標準処理へ渡さない。実受信の正しい列がそろわなければPASSにしない。配送自体や全画面のhitを保証しない。legacy session smoke/E2Eの安全条件とAPIは変更せず、通常入力成功や本体E2Eを実証済みとはしない。
