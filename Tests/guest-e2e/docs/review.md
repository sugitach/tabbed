## 0.11追加分の自己レビュー（guest未実行）

本体ソースを変更せずbuildし、署名済みcopyの実行ファイルhashを生成source/Resourceの両方へ固定。shellとRunnerでbundle/hash/署名を確認し、任意パス/PIDの実行入口は追加しない。E2Eは独立したexact invocationであり、旧probeから自動で本体へ進まない。

入力はFixture Aの実AX hitと現在のcontent/CG枠内、同一run/PID/ID・前面/画面/権限を毎回確認。入力lease/watchdogのlockと解放順は保持し、複数step用audit上限を16から64へ拡大した。drag-out解除は本体の既存remove/dissolve経路を実入力で通り、内部関数の呼出しや窓位置の直接修復はしない。group/解除の外部判定には専用2窓と本体所有stripの出現/消失を併用する。結果のrun/modeと3記録PIDの終了もscript側で確認する。

176 pure assertions・媒体25ケース・3app型検査/build/strict署名/ISO往復は成功。これは独立agentレビューやOS実証ではない。今回は追加agentを使用していない。前面変更の競合、AX hitがdrop overlayをどう返すか、通常QuitメニューのAX公開、drag-out/復元の実OS挙動はguest実行まで未確認。overlayのAX遮蔽や権限不足は例外で通さず停止する。媒体固定後の追記のためSOURCE.ZIPにはその時点の旧review記録が入る。

以下は過去のレビュー記録。

# Independent source review

## 0.8 window metadata追加の自己レビュー（guest未実行）

既知の未割当を対象に、processWindowIDをInputLeaseへ固定で渡す。正PID/非ゼロwindowIDの組だけを受理し、未指定ペアは従来sessionに限定する。片側欠落は停止。全mouse post（down/drag/通常up/watchdog up）共通のlock内でSDK公開enum2件だけを設定し、flagsChangedにはmouse fieldを付けない。判定の拒否例はpure policy testに追加した。releaseの事前確保・ロック・watchdog、送信前のPID/窓/前面/画面/安全領域確認は保つ。イベント送信先が同じPIDという制約は変わらず、sessionへの自動切替もない。

Fixtureのhandler/gate/trace/PASS条件は変更しない。NSApplication.postEvent、NSWindow.sendEvent、NSView.mouseDownなどをdriverやfixtureから直接呼び、OS配送の代わりにする経路は追加していない。公開APIの存在と、その2fieldがwindow routingに十分という実OS保証は区別する。具体的な根拠・既存実装との差・失敗時の切替条件はREADME参照。今回も自己レビューで、独立担当の新レビューやguest実行はない。新しい証明書、entitlements、TCC直接編集、権限自動要求は追加しない。

## 署名識別の読み取り調査（0.7権限停止後）

保存済み0.2/0.4/0.5/0.6/0.7の署名表示を読み取り比較した。bundle IDは全てdev.local.TabbedGuestHarness、guestの固定導入先は同じ。package.pyは両appへcodesign --sign - --options runtime --timestamp=noneを使い、TeamIdentifierはなく、埋込みentitlementsもない。designated requirementは各版のCDHashだけを指定していた。0.6はbf4f02e11a72541247324a209bae16dd45accf7d、0.7はc413e58f24b7d73bfc8976df41a565e7cfec7b87。0.6の要件での読み取り検証は0.6で成功、0.7でexit3（指定requirement不一致）。アプリは起動していない。

Apple DTSは[TCCの継続識別には安定した署名identityが必要で、unsigned/ad-hocを避ける](https://developer.apple.com/forums/thread/718331)と説明する。今回のCDHash依存と各版の再登録後にpreflightが通った履歴はこの仮説と整合する。ただしguest TCC内部の記録、Launch Services/旧コピーの影響、今回の拒否理由は読み取っておらず、個別原因の確定とはしない。

最小案は当面同じ0.7バイナリを固定し、反復buildが必要になったら承認された同じ開発用署名identity・bundle ID・配置先を継続し、異なる2buildが同じ署名者を含むrequirementを満たすか検証すること。証明書の利用可否は未確認。証明書作成・Keychain変更・TCC直接操作・OS設定変更はこの調査では行っていない。署名要件の緩和や権限確認の省略を提案するものではなく、guestでの許可とpreflightは引き続き必要。

## 0.7 配送観測追加の自己レビュー（guest未実行）

今回も実装担当の自己レビュー。process probeだけに自アプリlocal monitorとwindow入口/gate/出力の観測を加え、monitorは元のeventを返す。global監視や入力内容の収集は加えない。最大128行で停止し、初期記録とmonitorの用意をhandshakeで要求する。出力障害はFixture終了とし、driverは完全なreceipt write完了も確認する。旧diagnose-point/legacy session経路のhandler制限は変えない。

InputLeaseのevent生成・field設定・postToPid/session分岐・release/watchdogは維持し、既存lock内でraw fieldを読むだけ。監査配列は最大16行、I/Oはlock内でもdown/up間でも行わない。数値を文字列で保存し、異常座標のログ自体のJSON失敗を避ける。Fixture側では既存input.jsonのencode/writeの前後に記録し、そこで失敗した場合も区別する。監査追加の処理時間という観測の影響は残る。

通常modeのCUA対照は共通handlerの実測であって、この専用modeとpostToPidの成功証拠ではない。local monitorはAppKit dispatch地点の観測で、それ以前のOS配送を完全には観測しない。field 91/92の必須設定、実カーソルとevent.locationの関係は未確定として観測にとどめる。新しい独立レビュー、guest実行、追加権限変更は今回行っていない。

以下の5件は0.1版のレビュー結果。0.2移行・スクリプト開始差分の再レビュー結果は末尾。

独立レビュー担当がソースだけを読んで、操作スコープ、解放処理、誤認、副作用を確認した。担当は実行・ビルド・GUI・VM・ネットワーク操作・ファイル変更を行っていない。

指摘と対処:

1. 非ゼロlayerのfloating windowを見落としていた。全非負layerを調べ、不明な被覆は停止。唯一の例外をpinned Tabbedの既知drop indicatorのPID/layer/frameに限定した。
2. preflight失敗で前回runのresultを上書きする経路があった。毎回、preflight前にdirectory/runID/mode/観測frameをリセットし、前回ログへ書かない。
3. 復元判定が座標だけだった。AXMinimized=falseとWindowServer on-screenを追加。
4. 最終PASSログの書き込み失敗後にresult=PASSを書けた。最終logの直後にキャンセル/deadlineを再確認し、ログ失敗ならPASS結果へ進まない。
5. Launch Servicesのcallback待ちが取消不能だった。待機側に10秒timeoutとキャンセルを追加。OSへ送った起動要求自体は取消不能なので、未確定の起動結果を明示し、応答前の再試行を禁止する。

5件すべてについて独立担当の再確認で修正済みとの回答を得た。最終ソース再確認では、残るblocking safety issueは指摘されなかった。drag tap readinessと入力解放後のsession状態確認についても、操作対象を広げず条件を強めるものと確認された。

入力処理には、解放イベント事前確保、post/releaseのlock直列化、main/AX待ちから独立した3秒watchdogを追加。正常時はOSのCommand/左button状態も確認する。失敗時にはfixture/Tabbedを強制終了せず、位置の自動修復もしない。

なお、これらは静的レビュー。guest内イベント配送・UI・TCC・実ウィンドウ挙動を試験済みとはしない。

## 0.2 差分の独立レビュー

CLI開始条件・UUID排他作成・preflight失敗結果化・スクリプトを読み取りレビューした。配布処理がbuild成功と成果物不変性を確認していない問題を修正した。全工程成功後のみbuild-success.jsonを書き、packageでstatus/schema、全build/sourceファイルのinventory/hash/modeを照合する。compileとREADME/TEST.SH包装は保存済みsnapshotだけから行う。再レビューでblocker解消・追加blocking issueなしとの回答を得た。補強として入力hashとsnapshotの直接照合も追加した。READMEには旧版承認を新版に引き継がないこと、manual UIを閉じてscript runすること、外部ISO hashを照合することを記載。これはソースレビューであり、0.2のguest実行成功を意味しない。

## 0.3 差分の自己レビュー

今回の0.3は実装担当による自己レビューであり、新しい独立レビュー完了とは扱わない。起動時の一時的な座標不一致だけを上限付きで観測し直し、対象不一致・AX失敗・無効矩形・画面変更は即停止する。従来の3ポイント一致を維持し、時間的安定を最初のサンプルとの比較で確認するため累積ドリフトは受け入れない。入力保持中には待機を挿入せず、既存lease/watchdog/releaseを維持する。

AXとCGを照合した後にAXを読み直す経路を除き、入力点の空白コンテンツ内判定・最前面CG ID・system-wide AX hitを追加した。OS側の確認と送信の間の競合は残る。E2Eのdrop indicatorがAX hitを遮る場合には停止し、別アプリを許容する新しい例外は設けていない。

prepareは存在しないReadOnlyキーから実際のWritableキーへ修正し、両方明示falseのみ受理する。25組の負例/正例をshellで検査する。型検査・pure tests・署名媒体検証とguest動作実証は分ける。調査の根拠と未実証点は[調査記録](geometry-investigation-20261021.md)を参照。

## 0.4 個別process probeの自己レビュー

段階2の送信先はpreflightの内包Fixture署名/hash、Launch Servicesのプロセス、handshakeのPID/2つのID/識別子で固定する。CGEvent.postToPidに正のPIDだけを渡し、session postingへのfallbackを設けない。既存session経路を使う旧smoke/E2Eとはmodeを分離する。AX権限は個別probeでは使わず、event-postのみをpreflightし、不足時に自動要求しない。

各入力前に同じFixtureが前面/生存し、入力点がその空白領域とCGの最前面ID/ownerPIDに属することを確認する。AX/CG全矩形の一致には依存しない。releaseも同じPID宛てに送り、Command付きはFixtureがflags=falseを受信したことを合格条件にする。leaseのlock/watchdog/Stopは維持する。プロセス死亡・PID再利用など確認と送信の間のOS競合の絶対排除はできない。

自己レビューのみであり、新しい独立レビューとはしない。純粋テストはシナリオ引数、別窓・別修飾・順序違い・クリック/ドラッグ混同・解除欠落・余分な入力の拒否を検査する。実OSでのprocess posting・flags受信・event tag保持は未実証。成功してもsession tapやTabbedの動作確認とはしない。

## 0.5 入力なしの地点診断の自己レビュー

実装担当の自己レビュー。正確なCLI選択を別enum caseにし、診断と入力/E2Eの混在をRunner入口で拒否する。診断分岐はFixture起動・handshake・読み取り記録後にreturnし、InputLease生成とTabbed起動へ到達しない。診断起動UIのsmoke/E2Eボタンは完了後も無効で、beginにも再確認を置いた。stop/finallyのreleaseはleaseがnilのためイベントを送らない。

CG候補のraw順序・ID/PID・bounds・layer/alpha（欠落と既定値も区別）、判定結果、前面PID前後、画面/scale、AX hitを保存する。AX messaging timeout設定は診断クライアント側の待機制限であり、対象ウィンドウへのAX属性書き込みはしない。AX許可の要求やTCC変更、画面撮影、ネットワーク、シェル実行を追加していない。他アプリの窓タイトル・文書内容は読まない。各観測は順次取得なので、同時性や真のマウス配送先を断定しない。0.4のtopWindowと通常入力経路の条件・許容値は変更しない。

CLIの診断専用選択、余分なtransport指定拒否、guest確認欠落拒否を純粋テストで追加。全84項目と媒体判定25ケース、型検査・署名・媒体往復が成功した。これはguest診断の実行成功ではない。独立レビューは今回実施していない。成果物のSOURCE.ZIPはこの追記前に固定され、自己レビューのこの結果追記は含まない。
## 0.6 process probe修正の自己レビュー（準備時点）

既知Dock名・PID・layerのallowlistや全非0layer除外は設けない。process probeのglobal最前面確認のみを除き、全送信・releaseの固定PID経路は変更しない。入力直前の画面/scale再確認とFixtureのprocess専用mode handshakeを追加する。NSWindow入口の受信側gateはprocess modeだけに適用し、tag不明・別窓・境界/タイトルバー・空白以外のhitを標準処理へ渡さない。legacy session/E2Eのhit検査・Fixture処理は維持する。

NSView.hitTestはsuperview座標で呼び、空白boundsはcontent座標で検査する。tagや座標変換が実OSで期待どおり保持されるかは未実証。実受信のwindow ID・tag・event列・修飾/releaseがそろうまで成功にしない。PID再利用・OSプロセス死亡・権限失効など既存の競合制約は残る。追加権限、cursor warp、global postingへの自動fallbackは追加しない。今回も自己レビューで、新しい独立レビューは行っていない。

最終0.6の非GUI検証は98 assertions・媒体判定25ケース・両typecheck/build・署名・ISO往復が成功。受信側の実content座標/bounds/blankHitを同じreceiptへ追加し、初回の拒否でも生の判定材料を残す。InputLease/Observationの0.5とのバイト一致を確認した。実OSのpostToPid配送・NSEvent tag/座標・hitTest呼出しを実行した検証ではなく、guest導入・実行は別途確認待ち。この結果追記は完成済み媒体snapshotには含まない。
