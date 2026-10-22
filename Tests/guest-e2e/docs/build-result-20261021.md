# 0.2 host build と媒体検証（2026-10-21）

## 最新実測: auto-add OFF後、group操作直後の解放検査で停止

同一0.11を1回実行し、groupの入力後にOS押下状態検査で停止。送信auditのmouseUp/Command解放とFixtureの解放受信は確認したが、group結果の自動検証と後続の解除/regroup/Quit復元は未完了。追加権限・build・再送なし。失敗画面/3app/窓/ログを保全。[今回の証拠と未確認点](#011-auto-add-off後の再実行group後の解放状態検査で停止)。

## 履歴: 0.11導入後の初回E2Eは入力前に停止

同一媒体の検証導入と同Harness/Tabbedのguest許可再登録は完了。初回E2Eはauto-add保存設定ONのためpreflight停止。Fixture/Tabbed起動・入力・group/解除/regroup/Quitは未実施。設定や版を変えて再試行せず、結果UIとログを保持した。[詳細と残存状態](#011-guest導入許可更新と初回preflight停止)。以下は準備時点と過去の記録。

## 最新準備: 0.11本体E2Eの固定媒体完成（guest実行承認待ち）

本体ソースを変更せず、グループ化→drag-out解除→再グループ化→通常Quitと復元の単独E2Eを実装。176 pure assertions・媒体25ケース・最新本体を含む3app型検査/build/署名・実ISO往復が成功した。選定ISOは `exports/20261021T101722Z/Tabbed-Guest-Harness.iso`、SHA256 `e06a4a04ccb046d4ffa5980b409fcfd4e24bb10e93a135e29d6cdc36fca31335`。guest導入/実行/許可変更は未実施。[最終hash・必要な承認範囲](#011最終成果物と実行承認待ち)。以下は過去の段階を含む記録。

## 最新結果: 0.10のCommand-clickとCommand-dragが成功

ユーザー本人の直接確認後、導入済み0.10で⌘クリック1回、成功後に⌘ドラッグ1回を実行し、専用Fixtureで両方PASS。押下/マウス/解放の受信・flags・座標を確認し正常終了した。追加build/導入/権限変更なし。Tabbed本体E2Eは未実施。[今回の詳細](#追記-010のcommand-clickとcommand-drag成功)。以下は各段階の履歴。

## 最新の実測: 0.8は公開window fields保持後もNSEvent.window未割当

0.8の導入・実行と必要な同Harnessのguest入力権限再登録へのowner👍が正規readで確認されたとの委譲に従って実施。ホストで指定ISO `exports/20261021T071804Z/Tabbed-Guest-Harness.iso` のSHA256 `60ac90f3c92d5b35a5feb54f034179b726f282e3b66f52107b5e8e86858ca4a2` を再照合した。開始時はguestスクリーンセーバーだったがEscapeで作業画面へ戻り、ロック設定は変更しない。guest pgrepでHarness/Fixture/Tabbed一致なし。未保存TextEdit（Tests表示）と旧ログを保持。

UTM媒体選択は既知の「開けませんでした」通知となったが再要求せず、guest実媒体でHARNESS.ZIP SHA256 `adf4672049475debd9e4a01a63e26209e265b73340f8f3b84ebcc0e7e525a81c`、Media/Volume Read-Only=Yesを確認。旧0.7のHarness hash一致と保全先不存在を確かめ、`~/tabbed-guest-harness-test-v07-7e7e4fcc` へmv -nで保全。prepareが固定新規ディレクトリへ展開し、媒体全項目・bundle全項目hashと内外strict署名を検証してVERIFIED_INSTALLATION_ONLYで完了した。

署名識別が変わるため、今回承認された範囲で実行前にguest正規SettingsのAccessibilityで旧Harnessだけを削除し、既存guest認証後に検証済み固定パスの0.8を追加した。ON表示を確認し設定を閉じた。既存Tabbed Quit Fixの許可は不変更。新種類の権限要求、host権限、証明書/Keychain、TCC直接編集、隔離変更は行わない。認証情報は記録しない。設定UIの表示反映に遅延があり、操作完了を確認しながら進めた。

開始前に再度guest pgrepで対象3process一致なし。`bash /volumes/tabbed-guest-harness/test.sh run plain-click --confirm-isolated-guest` を1回だけ実行。run ID `A8D8DF5B-1765-4E1B-813E-3788DF2ABEEF`、mode PROCESS_INPUT_PROBE_plain-click。macOS26.6.2/build25G83、arm64、VM flag1。STARTログからevent-post preflight通過を確認。Fixture handshakeはPID4641、processProbe=true、deliveryTraceReady=true、A=522/B=523、初期frameはA=(30,467,360,270)/B=(470,467,360,270)、content offset=(0,32,360,238)。

| 境界 | 観測 |
| --- | --- |
| 送信 | PID4641/window522、CG(210,618)、tag92665031447118、flags0。down/upのbefore-postとpost-returned両方でwindowUnderPointer/windowCanHandle=522。downのclickState=1、up=0。targetPIDField=0 |
| カーソル | AppKit座標の前後は共に(571.99609375,690.0078125)。warp/mouseMovedは加えていない |
| AppKit local monitor | tag付きdown/type1とup/type2をPID/cgTargetPID4641で記録。CG(210,618)、nsLocation(210,264)、window fields2件=522を保持。それでもnsWindowNumber=0/nsEventWindow=nil |
| NSWindow入口 | 対応するtag付きmouse eventのwindow-entryなし。通常のtag0/nsType13では実window522/523へのwindow-entryあり |
| gate/出力 | receiver-decision、input-write-start/ok/errorなし、input.jsonなし |
| 最終判定 | STOP_OR_FAIL、NSCocoaErrorDomain260/POSIX2（input.json不在）。PASSではない |

window fields91/92の値が配送途中で消えたわけではなく、保持された状態でもNSEventのwindow割当が起きなかった。この2fieldだけで振分けが成立するという仮説は、今回のVM/構成では支持されない。アプリ未到達・権限不足・receiver gate拒否・JSON書込み失敗を原因とはしない。必要なwindow metadata/APIや通常session経路の採用は未確定で、ここから未知fieldを追加する反復へ進まない。nsLocationはwindow=nilのeventの値で、content座標とは解釈しない。

初失敗で停止し、同run再送、⌘click/drag、本体E2E、session切替、private API、追加修正/新版作成は行っていない。ログはguest `~/Library/Application Support/TabbedGuestHarness/A8D8DF5B-1765-4E1B-813E-3788DF2ABEEF/` に保持。最終一覧はdriver.jsonl=2773 bytes、fixture-delivery.json=3812 bytes、fixture.json=598 bytes、result.json=852 bytesだけ。input.jsonは正常終了後もなし。fixture-delivery.jsonのguest端末表示SHA256は `793d93efc8ad57ed8b868f8ef75c9d2e5529d76600f11dc64f9c3b730db0da84`。本記録はCUA画面の転記で、元ログをホストへ転送したものではない。Terminalへ移動した際のtag0のactivate/deactivate関連eventは合成mouseの受信と分ける。

専用CloseでこのrunのFixtureを通常終了し、Harnessも通常Closeで終了。最終guest pgrepでHarness/Fixture/Tabbed一致なし。mouseUpのAppKit到達は確認できたが、NSWindowでの受信・動作成功は未確認。稼働中の試験task/lease/watchdog、承認/認証待ちはなく失敗停止。VMは起動中、同一0.8の固定インストールとread-only媒体/再登録済みguest許可、全旧版・全ログ・未保存TextEdit・Terminalを保持。host設定/他アプリ許可/network/share/clipboard/clean VM/アカウント/ロック設定は不変更。commit/pushなし。

## 最新の準備: 0.8の公開window fields指定（guest未実行）

出力 `exports/20261021T071804Z`。配送に関する変更は、process probeのmouse eventへ公開enumのwindow fields91/92に検証済みAのwindow IDを設定することだけ。正PIDと非ゼロIDのペアを必須にし、down/drag/通常up/watchdog upへ同じ窓を指定する。partial destinationをsessionに切り替えない。postToPid、座標・tag・flags・pause、release/watchdog、受信handler/gate/trace、合格条件は維持。実OSでwindowが割り当てられる保証はなく、この仮説の検証候補である。

SDK26.5/arm64/macOS14.0、両appは0.8.0/build8。`bash Tests/guest-e2e/test.sh host` が両型検査/build、純粋ポリシー105 assertions（既存98＋PID/windowペアの正負7件）、媒体判定25ケース、ad-hoc/runtime署名とstrict検証、実ISO→ZIP→dittoによる全payloadバイト・app/source全パス/バイト/モード・両署名の再確認まで成功した。Python AST/shell構文とgit diff --checkも成功。AppKit/AX/入力を含むアプリをホストで起動せず、入力送信・guest操作・権限変更も行っていない。既存の本体内部回帰/XCTestの再実行はしていない。

| 成果物（出力ディレクトリからの相対パス） | SHA256 |
| --- | --- |
| `Tabbed-Guest-Harness.iso` | `60ac90f3c92d5b35a5feb54f034179b726f282e3b66f52107b5e8e86858ca4a2` |
| `payload/HARNESS.ZIP` | `adf4672049475debd9e4a01a63e26209e265b73340f8f3b84ebcc0e7e525a81c` |
| `payload/SOURCE.ZIP` | `2a021609880232f8376aed03e01f32ab8f988f309b72f0cfaccf99396bfc5e89` |
| `signed/Tabbed Guest Harness.app/Contents/MacOS/Harness` | `414290664c8414af3ac31de17c13301b43436cc047fe3457c9f59fc0a3c3bf2d` |
| `signed/Tabbed Guest Harness.app/Contents/Helpers/Tabbed Guest Fixture.app/Contents/MacOS/Fixture` | `8a0566febe031bf8dab2714825d144c1b142c3585528286bfcbd060aec556f8c` |

ISOは921600 bytes、mode0444。完成直後に全artifact hashと現入力/source snapshotの一致を再確認した。Fixture/main.swift、DeliveryTrace.swift、Observation.swiftは0.7最終snapshotとバイト一致を確認。Sharedに宛先ペア判定を追加したためFixtureのビルド入力/実行ファイルhashは別となるが、受信処理の変更ではない。自己レビューの記録は[review.md](review.md)。独立レビューは今回行っていない。

0.8のHarness designated requirementはCDHash `501b92bc5ab43eb301d7a8f438912f871ce4e3fc` で、0.7の要件とは異なる。guest許可が継続する保証はない。次の具体承認対象は **上記0.8のread-only導入・全hash/署名確認・必要なら同Harnessだけのguest許可再登録・plain-click 1 run** をまとめた範囲。追加種類の権限/他アプリ/hostの設定/隔離変更は含めず、予期しない要求は停止。最初の失敗で止め、window0/nilが続けば未知fieldを足す反復へ進まない。⌘操作・本体E2E・session切替・自動再送は含まない。

根拠・通常session方式との比較・未確定事項は[README](../README.md)。Appleの公開API/SDKは2fieldの存在を裏付けるが、postToPidのwindow指定が普遍的に必須という契約までは確認できない。既存PID実装は同じwindow metadataを使う一方、click前のmouseMoved等もあるため、その成功主張を今回の構成へ移さない。通常session/HIDの先例は固定PID方式とは保証範囲が異なる。0.8では一つの配送上の変化に限定した。

SOURCE.ZIPと署名済みResourcesはbuild開始時のsnapshotを使用し、この完成結果とREADMEの結果追記は含まない。再現はリポジトリルートで `bash Tests/guest-e2e/test.sh host`、毎回新規timestampへ出力。全旧ISO/ZIP/署名済みapp/guestログは保全した。実行中のbuild/試験処理はなく、今回VMには触れていない。commit/pushなし。

## 最新: 同一0.7の権限再登録後、AppKit到達とwindow未割当を確認

0.7のguest入力送信権限再登録とplain-click 1回へのowner👍が正規readで確認されたとの委譲後に実施。新build/媒体交換/差し替えはせず、ホストISO SHA256 `8190e9bde9776d9ce282c86ff3f69df833205eda685458627e2433ee7cf77a39` とguest verifyの全bundle hash・内外strict署名を再照合した。保存済み署名の読み取り調査は[review.md](review.md)に記録した。

guest正規System Settings UIのAccessibilityでHarnessだけを選択して削除、既存guest認証を終え、固定 `~/Tabbed-Guest-Harness-Test/Tabbed Guest Harness.app` を追加した。ON表示を確認して設定画面を閉じた。既存Tabbed Quit Fixの許可は不変更。追加の種類の権限、host権限、TCC直接編集、証明書/Keychain操作はない。設定一覧の移動と反映には遅延があり、表示を確認しながら進めた。UIのONだけでは成功とせず、後続preflightと受信を別判定した。資格情報は記録しない。

開始前のguest pgrepでHarness/Fixture/Tabbed一致なし。既存0.7の `bash /volumes/tabbed-guest-harness/test.sh run plain-click --confirm-isolated-guest` を再登録後に1回だけ実行。run ID `7E7E4FCC-BA5D-4785-94B1-F017EA9C67B9`、mode PROCESS_INPUT_PROBE_plain-click。STARTに到達しevent-post preflightは通過した。FixtureのhandshakeはPID4124、processProbe=true、deliveryTraceReady=true、A=477/B=478。初期CGフレームはA=(30,467,360,270)、B=(470,467,360,270)、content offset=(0,32,360,238)。

送信先は同じPID4124、予定点CG(210,618)、tag `92665031447118`。driverはtype1/downとtype2/upについてbefore-post/post-returnedを記録し、flags=0、targetPIDField=0、windowUnderPointer=0、windowCanHandle=0。送信側のclickStateはdownが1、upが0で、前後の観測で同じ。cursorAppKitBefore/Afterは共に(571.99609375,690.0078125)で、予定点とは別位置のまま。カーソルの移動は追加していない。APIの返却自体を受信ACKとは扱わない。

| 境界 | 今回の観測 |
| --- | --- |
| 初期記録/local monitor | output-readyとlocal-monitor-installedが存在。handshakeもready |
| AppKitのdown（trace index7） | uptime23457.28577441667、nsType=1/cgType=1、PID/cgTargetPID=4124、tag一致、CG=(210,618)、nsLocation=(210,264)、nsFlags=0、nsWindowNumber=0、nsEventWindow=nil |
| AppKitのup（trace index8） | uptime23457.420704291668、nsType=2/cgType=2、PID/cgTargetPID=4124、tag一致、CG=(210,618)、nsLocation=(210,264)、nsFlags=0、nsWindowNumber=0、nsEventWindow=nil |
| NSWindow入口 | 対応するtag付きmouse eventのwindow-entryなし。別のtag0/nsType13（AppKit-defined）ではwindow477/478へのwindow-entryあり |
| gate/encode/write | receiver-decision、input-write-start/ok/errorは記録なし。input.jsonなし |
| 最終結果 | STOP_OR_FAIL、NSCocoaErrorDomain260/POSIX2: input.jsonがない。PASSではない |

したがって今回のイベントはFixtureのAppKit dispatchまで到達しており、「OSがprocessへ配送しなかった」とする仮説は今回のdown/upには当てはまらない。観測上の欠落はwindow未割当/振分けとNSWindow入口の間にある。なぜwindowがnilなのか、event fieldsや座標/実カーソルとの関係、必要な修正は未確定。受信gateが拒否した・JSON書込みで失敗したという証拠もない。nsLocationはwindow=nilのイベントの値であり、Fixtureのcontent座標として扱わない。通常modeのCUA対照成功、process modeのAppKit到達、対象windowの受信成功を区別する。

最初の失敗で停止し、再送・修飾click/drag・session経路への切替・本体E2E・新修正/新buildは行っていない。Fixtureは終了操作まで生存して画面に2枚が残り、入力のdown/up以外に試験用の入力を追加していない。ログ読取りのためTerminalへ移動した際のactivate/deactivateに伴うtag0のAppKitイベントもtraceに含まれるが、合成tagの受信とは別である。

ログはguestの `~/Library/Application Support/TabbedGuestHarness/7E7E4FCC-BA5D-4785-94B1-F017EA9C67B9/` に保持。最終一覧はdriver.jsonl=2639 bytes、fixture-delivery.json=3805 bytes、fixture.json=598 bytes、result.json=852 bytesだけ。input.jsonは正常終了後も存在しない。guest端末で確認したfixture-delivery.json SHA256は `14b1f98496b54c029ec159a8e230cd33161bb0a7d58fdc070798946aaf5fc7b6`、fixture.jsonは `6fb5074b37a57e1d42a7b2b876eb3a3d5788e65e60653da17eda7ff9c80b964d`。本記録はCUA画面の転記で、元ログファイルはホストへ転送していない。

専用Closeで今回のFixtureを通常終了し、Harnessも通常Closeで終了。最終guest pgrepでHarness/Fixture/Tabbed一致なし、試験task/lease/watchdogの稼働なし。mouseUpはAppKit local monitorで確認できたが、NSWindowでの受信は確認できない。VMは起動中、同一0.7固定インストール/read-only媒体/再登録済みguest許可、全旧版とログ、未保存TextEdit（Tests表示）とTerminalを保持。host権限・隔離・他アプリの許可・clean VM・アカウント/ロック設定は不変更。承認/認証待ちではなく失敗停止で、commit/pushは行っていない。

## 直前: 0.7導入と初回plain-clickのpreflight停止

対象メッセージへのユーザーの👍が正規readで確認されたとの親からの委譲を受け、指定ISO `exports/20261021T062123Z/Tabbed-Guest-Harness.iso` の導入と既存権限でのprocess専用plain-click 1回だけを実施した。ホストでISO SHA256 `8190e9bde9776d9ce282c86ff3f69df833205eda685458627e2433ee7cf77a39` を再照合。開始時点でguestのHarness/Fixture/Tabbedプロセスはなく、旧ログと未保存TextEdit（Tests表示）を保持した。

UTM外部媒体選択は今回も「ファイルを開けませんでした」と返し、マネージャには旧Tabbed-Quit-Fix.iso名が残った。接続操作は繰り返さずguestを確認し、実媒体のHARNESS.ZIP SHA256 `9aacd93ddcbdd2dee4028aa99afc40c3173e0f6c6da54a2ee3ef8b20551a2546` の一致、Media Read-Only=Yes、Volume Read-Only=Yes、全5媒体マニフェスト項目のOKを確認した。

ゲスト端末のshift文字転送で `~` がbacktickとなり、読取り確認コマンドが引用待ちになった。Control-Cもguestへ伝わらず、未完のコマンドは構文エラーで破棄して通常promptへの復帰を確認。以後は `cd` と絶対パスを使った。アプリ起動や変更コマンドの途中状態ではない。小文字UUIDへのglobも一致しなかったため、実在を確認した正確なパスを使い直した。これらの端末入力問題をHarness試験の再送や配送結果には数えない。

旧0.6の実行ファイルhash一致と保全先不存在を確認し、`~/Tabbed-Guest-Harness-Test` を `~/tabbed-guest-harness-test-v06-af77dc2e` へmv -nで保全。prepareが固定新規ディレクトリへ展開し、全bundle hashと両strict署名を検証してVERIFIED_INSTALLATION_ONLYで終了した。続けてguest実行ファイルSHA256を直接読み、Harness `9036e96291632605fda4a559a2e47e199d7c75cb7a6d28ed88a5ee752f50b053`、Fixture `8622f7d6ef6affede40b58644c7b94192094e0f9267636808a6dd6a9e422b621` の一致を確認した。ホストでのアプリ実行はない。

`bash TEST.SH run plain-click --confirm-isolated-guest` を1回だけ開始。run IDは `6A1BB027-42F8-427C-A53B-6BD9E92A2418`。guest UIはmacOS26.6.2/build25G83、arm64、VM flag1を表示し、結果は次のとおり。

```text
mode: PROCESS_INPUT_PROBE_plain-click
result: STOP_OR_FAIL: Guest event-post permission missing. No request or setting change was made.
frames: []
```

driver.jsonlにも同じSTOP/FAILの1行だけがあり、uptimeは22082.817354916668。STARTなし。runフォルダの全ファイルはdriver.jsonl（218 bytes）とresult.json（435 bytes）だけで、fixture.json、fixture-delivery.json、input.jsonはない。preflightはFixture起動/handshake/InputLease生成より前のため、合成クリックの送信・受信・各配送境界の新たな確認は未実施。これは配送失敗の実測ではない。権限不足で止める条件に従い、正規設定UIの再登録も再実行も行わなかった。署名変更と権限失効の因果は今回確定していない。

ログはguestの `~/Library/Application Support/TabbedGuestHarness/6A1BB027-42F8-427C-A53B-6BD9E92A2418/` に保全。端末表示のSHA256はdriver.jsonl=`6ef925bed3c58b3ac6e6ac5a8a46e90067ffa8bcca61799fcea614eafe202277`、result.json=`1d221cd05a6e69905052f1e1129eb22d71d9cce656d5a5675a6dd92adee4ce37`。これはCUA画面の転記で、元JSONをホストへ転送したものではない。

停止後はHarnessの赤い閉じるボタン（windowShouldClose→NSApp.terminateの通常経路）で終了し、最終guest pgrepでHarness/Fixture/Tabbed一致なしを確認した。稼働中の試験task/lease/watchdogや保留認証はなく、承認待ちではなく失敗停止。VMは起動中、0.7固定インストールとread-only媒体、全旧版/ログ、未保存TextEditとTerminalを保持。guest/host権限、network/share/clipboard、clean VM、アカウント/ロック設定は変更していない。修飾click/drag・本体E2E・ソース修正/再build・commit/pushは未実施。再開には同じ0.7のguest入力送信権限の扱いを別途判断する必要がある。

## 0.7 配送観測版の準備結果（以下は導入前の記録）

出力 `exports/20261021T062123Z`。SDK26.5、Swift5 mode、arm64/macOS14.0 target、両bundleは0.7.0/build7。`bash Tests/guest-e2e/test.sh host` で両型検査/build、純粋ポリシー98 assertions、媒体判定25ケース、コピーのad-hoc/runtime署名とstrict検証、実ISO→ZIP→dittoによる全payloadバイト/アプリ・source全パス/バイト/モードと署名の再検証が成功。ISOは921600 bytes、mode0444。ホストで実行した新規コードは純粋テストだけで、Harness/Fixture/VMは起動していない。

| 成果物（出力ディレクトリからの相対パス） | SHA256 |
| --- | --- |
| `Tabbed-Guest-Harness.iso` | `8190e9bde9776d9ce282c86ff3f69df833205eda685458627e2433ee7cf77a39` |
| `payload/HARNESS.ZIP` | `9aacd93ddcbdd2dee4028aa99afc40c3173e0f6c6da54a2ee3ef8b20551a2546` |
| `payload/SOURCE.ZIP` | `672873251ebffaa933a2442c0c66ae7e5f3f3157522bae9368fe8716fe1b762e` |
| `signed/Tabbed Guest Harness.app/Contents/MacOS/Harness` | `9036e96291632605fda4a559a2e47e199d7c75cb7a6d28ed88a5ee752f50b053` |
| `signed/Tabbed Guest Harness.app/Contents/Helpers/Tabbed Guest Fixture.app/Contents/MacOS/Fixture` | `8622f7d6ef6affede40b58644c7b94192094e0f9267636808a6dd6a9e422b621` |

0.6の最終snapshotとの差分を読み、InputLeaseの変更は上限付きのraw field読取り/監査配列だけで、event生成・設定・postToPid/session分岐・release/watchdogに変更がないことを確認した。Runnerの通常clickの0.12/0.3秒wait、Fixtureの専用gateも維持。送信側のファイルI/Oは解放後、Fixture側の観測はAppKit local monitor/NSWindow入口/gate/encode/writeに限定する。観測処理の時間的影響はある。自己レビューであり、新たな独立レビューは実施していない。

最初のhost型検査 `exports/20261021T062029Z` はログ用CGFloatのString変換で失敗。Swiftの明示的な文字列化へ修正し、新規出力で全工程を完了した。失敗ディレクトリは保全し、成果物として選択しない。これは非GUIコンパイルエラーで、guest失敗や承認拒否ではない。shell構文/Python AST、git diff --checkも成功。完了直後、source-sha256.jsonに対する作業ソース一致と完成した全artifact hashを再照合した。

次の実行候補は **この0.7をTabbed-Testへ導入し、既存権限のままplain-clickを1 runだけ**。送信fields→local monitor→window-entry→receiver-decision→write完了を照合し、最初の失敗で停止する。権限不足なら再登録せず報告する。合成入力、session経路、⌘入力、本体E2Eは現時点で未確認。今回guestへの導入/実行/操作/権限変更はすべて未実行であり、対象別の実行確認が次に必要。host権限・隔離・旧媒体/guestログ・未保存書類は不変更、commit/pushなし。実行中のbuildは残っていない。

再現入口はリポジトリルートで `bash Tests/guest-e2e/test.sh host`（新規timestampへ出力）。sources/commands/logsは上記出力内。SOURCE.ZIPはビルド開始時点のsnapshotで、この結果追記とREADMEの完成結果追記は含まない。実行案と一次資料・判別条件は[README](../README.md)を参照。

最終出力 `exports/20261021T024058Z`。`./test.sh host` は Command Line Tools SDK26.5 / arm64 / min macOS14 で Fixture と Harness の typecheck・build、純粋ポリシー22 assertions、コピーへの ad-hoc署名、両 strict verify、HFS+/ISO9660 raw ISO、実ISOからZIP展開したapp/source全path/byte/mode一致と署名再確認まで exit 0。ホストでアプリは起動していない。`build-success.json` は全工程成功後のsnapshot/build inventory/hash/modeを記録し、package側で必須照合する。失敗ビルド、差し替えバイナリ、差し替えsnapshotをpackageが署名前に拒否する負例を別出力で3件確認した。

| 成果物 | SHA256 |
| --- | --- |
| `Tabbed-Guest-Harness.iso` | `a5e400c7a6c13e595ed2633a2bac420261e3f67c4ac56a12bd1d65cfb3ab5883` |
| `payload/HARNESS.ZIP` | `18b0903364f8aba8099eb27b3d951f8bd7faef466b6db936e236bc1f26c562af` |
| `payload/SOURCE.ZIP` | `09666a6ad26b105fb1794c8bef57f2644653004ad3059e883d31dc8046990a65` |
| `signed/Tabbed Guest Harness.app/Contents/MacOS/Harness` | `93b10029435a2b7f7ae44c041017eb0e469604148c86ee6cb4736644c5917303` |
| 内包 `Fixture` 実行ファイル | `63b7e99360a4073977e4df7b497da458ce950eca144199a32e6dc1768de848a2` |

`artifact-sha256.json` と `media-sha256.txt` を正とする。旧0.1ISOは変更せず保全した。0.2はguest未導入・未実行で、この媒体の静的検証はゲスト互換性やevent配送の証明ではない。旧0.1の初回guest smokeは入力前のAX/WindowServer幾何不一致で停止。[guest実測](guest-smoke-result-20261021.md)。0.2では不一致時に両フレーム値を残す診断を加えたが、この改訂実行には別途判断が必要。

この文書は完成した媒体の後に作成した記録で、媒体内のSOURCE.ZIPには含まない。成果物や旧履歴に上書きなし。commit/pushなし。
# 追記: 見直し後の段階2用0.4（2026-10-21）

以下は新0.4の非GUI準備結果。本文の旧0.2成果物はそのまま保全している。0.3は `exports/20261021T034338Z` に保全し、いずれもguestでは実行していない。

- 出力: `Tests/guest-e2e/exports/20261021T040511Z`
- ISO SHA256: `38cefcc4980015c68552a1922e7eb88dab748ae98a092b01e8206f6e6d591421`
- HARNESS.ZIP SHA256: `d4e408dd76d4fe144c034cf4cb5038d2216028e5ca4ca196961bfde121147167`
- SOURCE.ZIP SHA256: `ff795d083d0dd39f01f10dacd168343a63f36cad2c0c8d58594c522da03a2099`
- 署名済みHarness実行ファイル: `c2b10cff6dda4d53097a1f267700d591456a403eb8a7b4257a38c6c8ae4f700f`
- 署名済みFixture実行ファイル: `818af455431e482bb1afffa5d8811a1cf75baf40087ae9adb96986e825564d4f`

SDK26.5、arm64、macOS14.0 deployment target。2アプリの型検査・ビルド、純粋テスト81 assertions、shell媒体判定25ケース成功。署名はコピーへのad-hoc hardened runtime、内包/外側のstrict検証成功。実ISO→ZIP→dittoの全ファイル・パス・POSIX mode・source一致を確認し、両署名を再検証した。ISO原本は0444。コマンド・入力hash・build-success・各ログを出力内に保存。

再現入口はリポジトリルートから `bash Tests/test.sh guest host`。毎回新規出力で、既存ISOやログを上書きしない。上記hash文書は成果物確定後の追記のためSOURCE.ZIP内のsnapshotには含まれない。snapshot自体の内容はsource-sha256.jsonとbuild-success.jsonで固定済み。

次の承認対象は、このISOを隔離済みTabbed-Testへread-only接続し、既存版を上書きせず保全して新固定パスへ展開・hash/署名確認、必要なguest内Harnessのevent-post許可状態を確認したうえで、plain-click→command-click→command-dragを各1回ずつ別runで試すこと。最初の失敗で停止し、入力送信が不明な場合は再送しない。OSが追加権限を要求した場合は範囲を確認する。hostの権限、network/share/clipboard、別アプリ、Tabbed本体E2Eを含めない。成功してもprocess配送の確認であり、session tapや本体動作の実証ではない。

今回のturnではhostでアプリ起動、guest/UTM操作、権限変更、インストール、commit/pushを行っていない。ユーザーによるUTMの別ディスプレイへの移動は承知済みだが、こちらから位置や状態を変更していない。次のGUI操作では新しい画面・座標を確認する。

## 追記: 0.4のguest導入と初回plain-click結果（2026-10-21）

上の非GUI準備時点とは別の、対象限定承認後の実測。対象ISOと3probe各1回、必要な同Harnessのguest権限再登録が承認された。最初の失敗で停止する条件を適用した。

### 導入・権限

- ホストでISOのSHA256を再照合し、上記 `38cefcc4…591421` と一致。移動後のUTM画面を新たに取得して操作した。
- 既存Harness/Fixture/Tabbedが動作していないことをguestのpgrepで確認。旧0.2固定インストールは `~/tabbed-guest-harness-test-v02-4f5e5841` へ保全し、旧0.1・過去ログも保持した。
- UTMの媒体選択は「開けませんでした」と表示したが、再選択を繰り返さずguestの実媒体を確認した。`/Volumes/Tabbed-Guest-Harness/HARNESS.ZIP` のSHA256は上記0.4の `d4e408dd…147167` と一致した。UTM表示だけでは接続成功と判断していない。
- `bash /volumes/tabbed-guest-harness/test.sh prepare /volumes/tabbed-guest-harness` 成功。diskutilのWritableVolume/WritableMediaが両方false、媒体5項目・bundle全項目のSHA256一致、内包Fixtureと外側Harnessのstrict署名検証成功。`~/Tabbed-Guest-Harness-Test` へ新規展開し、prepare自身はアプリを起動していない。
- guestの正規設定UIと認証で旧Harness登録を削除し、検証済み固定パスの0.4を登録、AccessibilityのONを画面で確認。既存Tabbed Quit Fixの許可は変更していない。後述のSTART到達から、process probeのevent-post preflightも通過した。process probeはAXIsProcessTrustedを検査しないため、AX API自体の動作成功とはしない。
- guest: macOS 26.6.2（Build 25G83）、arm64、VM flag=1。ホスト権限・network/share/clipboard・clean VMは変更していない。

### 入力送信と受信の結果

実行入口は `bash /volumes/tabbed-guest-harness/test.sh run plain-click --confirm-isolated-guest` を1回。run IDは `66EF834F-C158-4980-88C0-AACAC4D06239`、modeは `PROCESS_INPUT_PROBE_plain-click`。

| 項目 | 実測 |
| --- | --- |
| plain-click | STOP_OR_FAIL: Unexpected foreground window at event point; no further input |
| ⌘クリック / ⌘ドラッグ | 最初の失敗で停止したため未実行 |
| 合成入力の送信 | 生成前に停止。受信記録での配送成功は未確認 |
| Tabbed本体 / session経路 / E2E | 未起動・未実行 |

driver.jsonlはSTART（uptime 14452.003112083334）と停止（14452.680250250001）の2件のみ。FixtureのPIDは2624、window IDは346/347、初期フレームはA=(30,467,360,270)、B=(470,467,360,270)。runフォルダにはdriver.jsonl（496 bytes）、fixture.json（552 bytes）、result.json（421 bytes）のみ存在し、input.jsonはない。resultのframesは空。ゲスト画面でこれらの内容・一覧を読み取った。

静的な停止位置は `Observation.topWindow` の未知ID/owner PID判定で、`runProcessProbe` の最初のvalidateから呼ばれる。最初のvalidateはInputLease生成・入力開始・probe送信ログより前であり、その送信ログも存在しない。従って今回の試験による押下・解放イベントは生成されていない。予期しない前面ウィンドウのID/PIDはこの版のエラーに記録されず、何が判定に当たったかは未確定。矩形差やアニメーション、別ディスプレイ移動が原因とは断定しない。修正・再実行・次版作成は行っていない。

### 保全と終了状態

元ログはguestの `~/Library/Application Support/TabbedGuestHarness/66EF834F-C158-4980-88C0-AACAC4D06239/` に保持。この追記は画面からの転記で、元JSONをホストへファイル転送したものではない。guest内で確認したSHA256は次のとおり。

| 元ログ | SHA256 |
| --- | --- |
| driver.jsonl | `baec1f843ec118766f6dee014618d49a3fad5a884eb8a160c68231b0ae87e58f` |
| fixture.json | `640b873602a5d9fc43d002d68f40525eb1adcb0fff7294a50bf05fc953e180d9` |
| result.json | `80fa1d64c4e0a54ccec6cf6a06dc5483f4064f30398a9528320bd8035a637168` |

専用「Close this run's test windows」で2枚のFixtureを閉じ、Harnessも通常終了した。その後guestのpgrepでHarness/Fixture/Tabbedの一致なしを確認した。試験処理や入力押下は残っていない。VMは起動中、Terminalと未保存TextEdit（Tests表示）は保持。0.4の固定インストール・guest権限登録・read-only媒体は残り、旧版と全ログも残る。資格情報は記録しない。commit/pushは行っていない。

## 追記: 0.5の入力なし診断媒体（guest未実行）

0.4の既存ログには不一致候補が残らず、Fixtureも正常終了済み。0.4の既存入口は入力を試みるprobeで、候補の記録だけを行うモードがない。再試行や旧成果物の改変をせず、診断専用 `diagnose-point` を0.5へ追加した。既存の入力判定・許容値を変えず、入力生成前に必要な観測を保存して終了する。原因はまだ確定していない。

新出力は `Tests/guest-e2e/exports/20261021T044218Z`。ホストCLT SDK26.5 / arm64 / min macOS14、2アプリの型検査・build、純粋テスト84 assertions、媒体判定25ケース、ad-hoc署名と内外strict検証、実ISO→ZIP→dittoの全path/byte/mode・source一致と署名再検証がexit 0。アプリはホストで起動していない。旧成果物・ログは上書きしていない。

| 成果物 | SHA256 |
| --- | --- |
| `Tabbed-Guest-Harness.iso` | `543d7d69f55bb80bd1020e439682fb57b79a09a4d0594c856e9938e95d95d624` |
| `payload/HARNESS.ZIP` | `ac832f77bc3e8df2be80d3b31de60e1880dff18736d89785b0b077eb40e72ba4` |
| `payload/SOURCE.ZIP` | `f42eebda9f1c2926bc7d54f219ed913f5a35abd8271d6c656357b6d63f809db0` |
| 署名済みHarness実行ファイル | `c95978fb0c03dc334a7558f61f92ddf2ca4ae21b3dfae5e7ff2703c3379fd135` |
| 署名済み内包Fixture実行ファイル | `fe8420a6c6c51b35f065bab8ef60a71f301938aacf9c8349dffe168637af6a5a` |

観測内容と入口はREADMEの「次の観測」を参照。ログは同じrunフォルダへ `point-diagnostic.json` として保存。Fixtureをactivateし0.4秒後に予定点を計算、CG snapshotとAX hitを各1回取得する。CG/AXにuptimeの区切りを記録するが原子的同時取得ではない。前回参照点(210,618)と新計算点、CG候補の返却index/ID/PID/ownerName/layer/alpha/bounds、最初の採用候補、前面PID前後、screen/scale、Harness窓の座標を残す。AXは既存許可だけで読み、不足ならAX_NOT_TRUSTED_NO_REQUESTを残す。窓タイトル・identifierは既知Fixtureに限定する。

次の具体的な確認対象は、このISOをTabbed-Testへread-only接続し、0.4とログを上書きせず保全後、固定パスへ0.5を展開してhash/署名を確認、既存guest権限のまま `run diagnose-point --confirm-isolated-guest` を1回実行すること。新たな権限設定・通常入力試験・Tabbed本体・隔離変更を含めない。別途必要と判明した権限変更はその時点で確認する。終了後にFixtureを保持して既存CUAの画面を直ちに取得し、観測点と照合する。アプリによる画面撮影はなく、新しいScreen Recording許可は求めない。CUA画面とJSON観測を同時刻と表現しない。

今回のturnはソース準備と非GUI検証・媒体作成のみ。guest操作・導入・新版実行・権限変更・イベント送信・本体E2Eは未実施。0.4の限定承認を0.5実行へ流用していない。実行拒否を受けた状態ではなく、対象成果物への確認待ち。診断結果が得られるまで通常入力の修正や再試行へ進まない。commit/pushなし。この追記は固定済みSOURCE.ZIPには含まない。

## 追記: 0.5入力なし診断のguest結果

上記準備後、ISO SHA256 `543d7d69f55bb80bd1020e439682fb57b79a09a4d0594c856e9938e95d95d624` に対する導入・診断1回の明示承認を受けた。ホストで同ハッシュを再確認。旧0.4を `~/tabbed-guest-harness-test-v04-66ef834f` へ保全し、全旧ログ・未保存TextEditを保持した。

UTM媒体選択は従来同様「開けませんでした」と表示したため、再要求せずguest実媒体のHARNESS.ZIPを照合。上記0.5の `ac832f77…0e72ba4` と一致し、prepareで媒体両Writableキーfalse、全SHA256、内外strict署名検証に成功。新固定パスへ展開し、権限は変更しなかった。スクリーンセーバーからの復帰は通常のVM内クリックで行え、認証やロック設定変更は不要だった。

実行は `bash /volumes/tabbed-guest-harness/test.sh run diagnose-point --confirm-isolated-guest` を1回のみ。run ID `F2051D56-FF31-45BC-A0B8-7FAA4F2021DA`、mode `POINT_DIAGNOSTIC_NO_INPUT`、result `DIAGNOSTIC_ONLY_NO_INPUT`。送信試験のPASSではない。

| 観測 | 値 |
| --- | --- |
| 診断予定点 / 前回参照点 | 両方(210,618)、guest左上原点のpoints |
| CG一覧の総行数 | 17 |
| 地点を含む最初の候補 | 返却index6、Dock、PID1744、window267、layer20、alpha1、bounds=(0,0,1869,882)、on-screen=true |
| 次の候補・期待対象 | 返却index8、Tabbed Guest Fixture、PID2871、window365、layer0、alpha1、bounds=(30,467,360,270)、on-screen=true |
| Fixture申告フレーム / 確認したCGフレーム | 両方(30,467,360,270) |
| 空白領域offset | (0,32,360,238) |
| 0.4と同じCG判定 | REJECT_UNEXPECTED_FOREGROUND（最初のDock行が期待ID/PIDと異なる） |
| 前面アプリ（観測前後） | ともにdev.local.TabbedGuestFixture、PID2871 |
| AppKit / CG画面bounds | ともに(0,0,1869,882) |
| AppKit visibleFrame / backingScale | (0,90,1869,762) / 2 |
| CGDisplayPixelsWide/High | 1869 / 882（pointにscaleを掛けず記録） |
| Harness窓 | window364、CG変換bounds=(15,35,950,310)、level0、visible=true、key=false |
| AX hit | AX_NOT_TRUSTED_NO_REQUEST。既存許可では信頼済みにならずhitは未取得、要求・再設定なし |

診断は約16015.121〜16015.126のuptime区間で観測した。CGとAXは順次取得であり原子的な同時スナップショットではない。診断保存後、他の操作を挟まずCUA画面を取得した。青いFixture Aの空白領域内に予定点があり、Harnessの矩形はその点に重ならなかった。画面の見た目と全画面DockのCG矩形を照合したが、見えている領域や実際にマウスを受ける領域をCG boundsだけで断定しない。

**確定したのは、今回の再現ではCGの矩形重なりとlayer/alphaだけを入力先判定に使うため、全画面Dockの行を採用して停止すること。** 実際のmouse hitをDockが奪うか、そのDock窓の用途・入力透過性は未確認。0.4には不一致IDが記録されないため、前回も同じIDだったとまでは確定しない。これはHarnessの送信前判定の問題で、CGEvent配送やTabbedの失敗を観測したものではない。Dockの一律除外、許容幅拡大、CGWarp等への先回り置換、追加の試験・修正・次版作成は行っていない。次の設計判断では実際のhitを確認できる根拠、またはPID宛てprobeとsession経路で必要な前提の差を検討する必要がある。

元ログはguestの `~/Library/Application Support/TabbedGuestHarness/F2051D56-FF31-45BC-A0B8-7FAA4F2021DA/` に保存。driver.jsonl=920 bytes、fixture.json=552 bytes、point-diagnostic.json=3612 bytes、result.json=364 bytes。input.jsonは生成されていない。point-diagnostic.jsonのguest端末表示SHA256は `faf4721582d1734ec018d2a9ce0a36a4e3d9b26b1bc917733bb08cafe2741887`。この文書は画面からの転記で、元JSONファイルをホストへ転送したものではない。

画面照合と読み取り後、専用CloseボタンでFixtureを正常終了しHarnessも通常終了。最後のguest pgrepでHarness/Fixture/Tabbed一致なし。診断処理は残らず、合成入力も生成していない。0.5固定インストール、read-only媒体、既存権限設定、旧版、全ログ、未保存TextEdit、Terminalは保持。VMは稼働中。ホスト権限・network/share/clipboard・clean VMは不変更。権限不足は観測結果であり、承認拒否や待機中の権限ダイアログではない。commit/pushなし。

## 追記: 0.6 process probeの最小修正（非GUI検証のみ）

最終出力 `Tests/guest-e2e/exports/20261021T050857Z`。0.5で観測したDock行の用途や入力透過性を推測して除外する修正は行わず、PID宛てprobeとsession入力の前提を分けた。process probeだけは他プロセスのCG全画面重なりを送信条件にしない。署名/hash・固定PID・窓ID・前面・CG対象窓内/on-screen・空白領域確認を維持し、入力直前の画面/scale再確認を追加した。

Fixtureを `--process-probe` の限定モードで起動し、handshakeに同modeがあることをDriverで確認する。FixtureのNSWindow入口で、left down/drag/upが正しいtag、Aのwindow ID、現在の空白boundsの12pt内側、NSView.hitTestの結果を満たす場合だけ標準処理へ渡す。受信point/content bounds/blankHitもinput.jsonへ記録する。tag欠落や別窓・範囲外は `rejected-*` とし、既存の厳密な受信列判定では成功にしない。このモード中の手動mouse操作もFixture内で拒否するので、終了はHarnessの専用Closeを使う。

InputLease.swiftとObservation.swiftは0.5 snapshotとバイト一致を確認した。固定PIDへの送信・release、watchdog/Stop、session/E2EのtopWindow/AX hit、通常の入力APIには変更がない。legacy Fixtureはmode=falseで同じ受信記録・通常dispatchを維持する。新たなAX/TCC設定、Dock/layer allowlist、CGWarp、global/sessionへの自動fallback、汎用診断基盤は追加していない。

APIの根拠は [Apple CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) とCLT SDK26.5のCGEvent.h（特定applicationのevent streamへのposting、PSN版の後継にPostToPidを指定）、[NSView.hitTest](https://developer.apple.com/documentation/appkit/nsview/hittest(_:))（NSWindowがmouse-down対象viewを決めるローカルなhit）。hitTestにはsuperview座標、boundsにはcontent座標を使う。これは送信先プロセス指定と受信側の安全確認であって、OSの配送成功・全画面のhit・session tapやTabbed受理の保証ではない。受信はNSWindow入口で観測し、BlankViewのmouse handlerやUI作用を個別に実証するテストではない。

SDK26.5 / arm64 / min macOS14。両アプリの型検査・build、純粋テスト98 assertions、媒体判定25ケース、コピーへのad-hoc hardened runtime署名、内外strict検証、実ISO→ZIP→dittoの全path/byte/mode・source一致と署名再検証がすべてexit 0。新たなテストはFixture起動scope、tag欠落・別窓・対象なし・タイトルバー/境界・非有限座標・hit不一致の拒否と、拒否受信をPASSにしないことを検査する。AppKit/AX/CGEvent postingをホストで実行したテストではない。送信先判定の修正と受信gateは自己レビュー済みで、新しい独立レビューは行っていない。

| 最終成果物 | SHA256 |
| --- | --- |
| `Tabbed-Guest-Harness.iso` | `4f5d854262d36dc64126772de182903a287f1f03d21693e33bb955094e6552d7` |
| `payload/HARNESS.ZIP` | `598c93ab772c1321b4897106ad7ea1359d04d43ef17dd4cc961fa488214e29ea` |
| `payload/SOURCE.ZIP` | `4cdc5d3b7dbe1f588464940cf3daf0981a26a76bfeb49968d14a57441935e0b2` |
| 署名済みHarness実行ファイル | `7d1027020fc3ece5febe3de488686f278a5be54ca5b545c7bf8efe33adb44f8c` |
| 署名済み内包Fixture実行ファイル | `830e2e358396d53683068492a8924b5f0681cf0c44612714da8bb99d0eed1369` |

旧0.4/0.5、準備途中の `exports/20261021T050652Z`、各ソースsnapshot・ログ・署名媒体は上書きせず保全。今回示す最終hashの対象は050857Zのみ。現README・結果文書の完成後追記は固定済みSOURCE.ZIPには含めない。build-successとsource-sha256が実際の入力snapshotを固定する。

次の具体的確認対象は、最終ISOをTabbed-Testへread-only接続、0.5と全ログを保全して0.6を固定パスへ新規展開・hash/署名確認し、既存権限のままplain-clickを1回実行すること。正しい受信が得られた場合だけ別runでCommand click、Command dragを各1回。最初の失敗で止め、権限不足なら設定を変えない。0.5のAX_NOT_TRUSTEDが署名変更に起因するかも、新版のevent-post許可が有効かも未確認。新バイナリ実行の包括承認とは扱わない。通常の既承認ソフト再実行の希望とは区別する。

このturnではguest/UTM操作、ホストでのアプリ起動、インストール、権限変更、入力送信、本体E2E、commit/pushは行っていない。ゲスト実行は確認待ちで、拒否された状態ではない。実行中のビルド・包装は完了している。

## 追記: 0.6 guest初回実行はevent-post事前検査で停止

最終ISO `exports/20261021T050857Z/Tabbed-Guest-Harness.iso`、SHA256 `4f5d854262d36dc64126772de182903a287f1f03d21693e33bb955094e6552d7` への具体的な実行承認後、既存権限のままplain-click→Command click→Command dragを各1回、最初の失敗/権限不足で止める条件で開始した。

導入前にguest pgrepでHarness/Fixture/Tabbed一致なしを確認。0.5固定インストールは `~/tabbed-guest-harness-test-v05-f2051d56` へ保全し、全旧版・ログを保持した。ホストISO hashを再照合し、guestの実媒体HARNESS.ZIPは `598c93ab772c1321b4897106ad7ea1359d04d43ef17dd4cc961fa488214e29ea` と一致。UTMは媒体選択に従来と同じ「開けませんでした」を表示したが、同じ要求を繰り返さず実媒体の内容で判断した。prepareは両Writableキーfalse、媒体全項目・bundle全項目hash一致、内包/外側のstrict署名検証に成功し、新固定パスへ展開した。

`bash /volumes/tabbed-guest-harness/test.sh run plain-click --confirm-isolated-guest` を1回実行。run ID `26D2E7F3-D150-43EA-A982-DB5DB8702DB0`、mode `PROCESS_INPUT_PROBE_plain-click`、結果は次のとおり。

```text
STOP_OR_FAIL: Guest event-post permission missing. No request or setting change was made.
```

CGPreflightPostEventAccessがfalseとなった。STARTログより前のpreflightであり、Fixture起動、InputLease生成、合成入力の生成/送信には進んでいない。driver.jsonlは同じ停止メッセージ1件のみ（uptime 17404.852877625002、218 bytes）。result.jsonは435 bytes、frames空。フォルダにこの2ファイルのみあり、fixture.json/input.jsonはない。Command click/dragは条件に従い未実行、同版再試行・権限登録や設定変更・追加要求・新バイナリ作成を行っていない。

これは0.6の受信gateやCGEvent配送の失敗を実証した結果ではなく、実送信前の権限検査による停止。0.5のAX_NOT_TRUSTEDと今回のevent-post falseが同じ理由か、署名変更で登録が有効でなくなったかは未確定。既存の設定UI上のON表示を実効許可成功と扱わず、検査の結果を記録した。自動承認レビューの拒否ではなく、ゲストOSの事前検査結果であり、権限ダイアログは保留していない。

元ログはguestの `~/Library/Application Support/TabbedGuestHarness/26D2E7F3-D150-43EA-A982-DB5DB8702DB0/` に保持。内容と一覧はCUAのゲスト端末で読み取り、hashもguestで表示した。この追記は画面転記であり、元JSONファイルをホストへ転送していない。

Harnessを正常終了し、最後のguest pgrepでHarness/Fixture/Tabbed一致なし。Fixtureは今回起動しておらず、入力押下や試験処理は残らない。VMは起動中、0.6固定インストール・read-only媒体・旧0.5以下・全ログ・未保存TextEdit（Tests表示）・Terminalを保全。ホスト権限、guest権限設定、network/share/clipboard、clean VMは不変更。コード修正・再ビルド・本体E2E・commit/pushなし。次へ進むには同じ0.6に対するguest権限登録の確認/再設定を別途判断する必要があり、今回は実施していない。

## 追記: 同一0.6のguest許可再登録後、通常クリック受信未確認で停止

同じ0.6のguest入力送信権限の再登録と試験再開への個別承認後に実施。ホストで最終ISOのSHA256 `4f5d854262d36dc64126772de182903a287f1f03d21693e33bb955094e6552d7` を再確認。guestのverifyで全bundle hashと内外strict署名を再照合し、固定パスHarness実行ファイルは `7d1027020fc3ece5febe3de488686f278a5be54ca5b545c7bf8efe33adb44f8c` と一致した。ビルドや差し替えはしていない。

guestの正規System Settings UIでAccessibilityの旧Harness登録を削除し、検証済み固定パスの同版を追加。既存のguest認証を用い、資格情報は記録しない。他アプリ（Tabbed Quit Fix）の登録は変更せず、ホスト権限・network/share/clipboard・clean VMも変更していない。追加後のHarness ON表示を確認し設定画面を閉じた。メニューや設定画面の反映には遅延があり、表示完了を確認してから進めた。

通常クリックの実行入口は同じ `bash /volumes/tabbed-guest-harness/test.sh run plain-click --confirm-isolated-guest`。再登録後は1回のみで、run ID `F242FBEF-FD55-46FD-A7F1-A148A5E33FEA`、mode `PROCESS_INPUT_PROBE_plain-click`。

| 項目 | 結果 |
| --- | --- |
| event-post preflight | 通過。STARTログに到達 |
| Fixture起動・handshake | PID3387、window409/410、processProbe=true |
| 予定点の前提 | A初期(30,467,360,270)、空白offset(0,32,360,238)。送信前のID/PID・前面・座標・権限検査を通過 |
| 通常クリック送信 | PID3387宛てのbegin/down、finish/up API呼出し経路に到達。OSでの配送・受信は未確認 |
| ソフト上の解放 | finishNormally後のinput.json読取りで失敗したため、同leaseの解放処理は通過。Command入力はこのscenarioでは送らない |
| 受信記録 | input.jsonなし。NSWindowの受信成功は確認できない |
| 失敗 | NSCocoaErrorDomain Code=260 / NSPOSIXErrorDomain Code=2、input.jsonが存在しない |
| 後続 | 最初の失敗で停止。Command click/drag、同版再送、修正/新版作成は未実施 |

driver.jsonlはSTART（uptime 19023.732570541666）、Process-only input probe（19024.312095416666、destinationPID3387/windowID409）、input.json読取失敗（19024.776171916666）の3件。InputLeaseはbegin/finishに失敗すればその時点でthrowするため、今回の読取位置への到達は両メソッドを通過したことを示す。ただしCGEvent postingは配送のackを返さず、実OSでmouseUpが受信された証明でもない。

失敗表示後、入力を再送せず同runの一覧と既存ログを読み取った。driver.jsonl=1295 bytes、fixture.json=572 bytes、result.json=852 bytesのみで、input.jsonはなかった。Fixture終了後の最終一覧でも同じ3ファイルのみ。resultのframesは空。Fixtureの2窓は表示されていたが、それを受信成功とは扱わない。0.4のDock最前面拒否や前回の権限不足とは異なり、今回は送信経路を通過した後の受信確認に到達した段階での失敗。イベントがOS・NSApplicationのrouting・NSWindow入口のどこまで届いたかは現ログだけでは切り分けられない。受信gateが拒否したと断定する材料もない（拒否したmouseイベントも通常はinput.jsonへ記録する構造）。

元ログはguestの `~/Library/Application Support/TabbedGuestHarness/F242FBEF-FD55-46FD-A7F1-A148A5E33FEA/` に保全。以前の権限不足run `26D2E7F3-D150-43EA-A982-DB5DB8702DB0` と全旧ログも保全した。この追記はCUA端末画面からの転記で、元JSONをホストへ転送したものではない。

専用Closeで今回のFixtureを正常終了し、Harnessも通常終了。最終guest pgrepでHarness/Fixture/Tabbed一致なし。試験taskやlease watchdogの稼働は残っていない。入力解放はソフトの処理通過として記録し、実受信で確認できたとはしない。VMは起動中、0.6固定インストールとread-only媒体、再登録済みHarness許可、旧版、全ログ、未保存TextEdit（Tests表示）、Terminalは保持。承認待ち・保留認証ダイアログではなく、失敗停止である。ホストでのアプリ起動、本体E2E、アカウント/ロック設定変更、隔離変更、コード修正、再ビルド、commit/pushは行っていない。

## 追記: 同一0.6で通常GUI入力の対照試験

NSWindow handlerと出力経路の切り分けとして、同じ承認済み0.6・既存権限・隔離維持の範囲で、入力なし診断を起動し自前青blank領域へ通常GUI clickを1回行う指示を受けて実施した。ホストで同一ISO SHA256 `4f5d854262d36dc64126772de182903a287f1f03d21693e33bb955094e6552d7` を確認。guestのTEST.SHが既存インストールの全bundle hash・内外署名を再確認し、diagnose-pointを1回起動した。新build・展開・権限変更はない。

run ID `AF77DC2E-08EB-4168-90FB-13029A19212B`。診断プログラムは `DIAGNOSTIC_ONLY_NO_INPUT` で終了し、Fixtureを残した。最新のCUA画面でrunの一致した青いFixture A（画面内x30〜390/y539〜778）を確認して、空白領域のCUA座標(210,658)へclick APIを1回のみ実施した。これはguest点(210,618)に対応し、クリック後にAがkeyになったことを画面でも確認した。追加のクリックやdrag APIは使っていない。

`input.json` が233 bytesで生成され、次の3イベントを記録した。時刻はuptimeの小数を丸めて示す。

| 順 | type | windowID | Command | tag | uptime（約） |
| --- | --- | --- | --- | --- | --- |
| 1 | down | 422 | false | 0 | 19919.8375 |
| 2 | drag | 422 | false | 0 | 19919.8470 |
| 3 | up | 422 | false | 0 | 19919.8868 |

CUAへのclick要求は1回だが、実際の受信列にはdragが1件含まれた。純粋なdown/upのみの列だったとは報告しない。tag0であり、Harnessの合成入力tagではない。FixtureはPID3522、A/Bの窓IDは422/423、processProbe=false。Aの初期フレームは(30,467,360,270)。共通のNSWindow.sendEventと通常のinput.jsonのJSON encode/atomic writeがこの対照入力で動作したことを確認できた。一方、processProbe=trueで行うcontent座標/hit検査と追加JSON項目、CGEvent.postToPidの配送はこの対照では検証していない。以前の合成入力runをPASSへ変更しない。

同runの診断JSONでは、予定点(210,618)のAX hitはAXError=0、PID/windowPID3522、role=AXWindow、subrole=AXStandardWindow、Fixture Aのrun付きidentifier/title、frame=(30,467,360,270)だった。再登録後の既存許可でこのAX読み取りは実行できた。CGの最初の重なり候補は引き続きDock（返却index6、layer20、alpha1、全画面bounds=(0,0,1869,882)）で旧判定はREJECT_UNEXPECTED_FOREGROUND。CG boundsの最前面判定とAX hitが一致せず、実際の通常VM入力はAに到達した、という今回の条件下での観測である。Dockを恒常的に除外してよいという一般化はしない。

診断result.jsonのDIAGNOSTIC_ONLY_NO_INPUTと `inputEventsCreated=false` は、診断プログラム自身が合成イベントを送らないことを示す。resultと診断JSONの保存後に別のCUA操作として対照クリックを行ったため、その後input.jsonが存在していても合成入力のPASSを意味しない。単独test.shのみでこの対照入力まで自動完了したという結果でもない。

ログはguestの `~/Library/Application Support/TabbedGuestHarness/AF77DC2E-08EB-4168-90FB-13029A19212B/` に保全。driver.jsonl=1228 bytes、fixture.json=573 bytes、input.json=233 bytes、point-diagnostic.json=4024 bytes、result.json=364 bytes。input.jsonのguest端末表示SHA256は `1a68c566131a161025b0fb543297b3c7c9907e445e3d2c57024a6d1308c0056c`。この文書はCUA画面の転記で、元JSONファイルをホストへ転送したものではない。

受信確認後に専用CloseでFixtureを通常終了し、Harnessも通常終了。最後のguest pgrepでHarness/Fixture/Tabbed一致なし。全ログ・旧版・0.6固定インストール・read-only媒体・既存許可・未保存TextEdit（Tests表示）・Terminalを保持。VMは起動中で、ホスト権限・guest権限・network/share/clipboard・clean VMは不変更。合成入力の再送、修飾入力、本体E2E、ソース修正/新build、commit/pushは行っていない。

## 0.9 媒体完成（2026-10-21、guest未実行）

中断時の通常session配送案を最小実装し、`bash Tests/guest-e2e/test.sh host` が完了した。CLT SDK26.5、arm64、deployment target macOS14.0。両appの型検査/build、純粋policy 111 assertions、媒体判定25ケース、ad-hoc署名検証、実ISOからのZIP/ソース/アプリ展開と署名・byte/mode往復検証が成功。ホストで起動した新規実行ファイルはSharedだけをリンクした純粋テストであり、Harness/Fixtureは起動していない。XCTest/Tabbed本体/VM操作は未実施。

成果物は `exports/20261021T081412Z/`。ISOは921600 bytes、mode0444。ハッシュ:

| 対象 | SHA256 |
| --- | --- |
| Tabbed-Guest-Harness.iso | `e7f28a952e388ff4a77e5707f10be04dc925bbbba323953329c8e2a4a787b699` |
| payload/HARNESS.ZIP | `f4c80f0cdcebb11f053a7d5a0bf1353d10e79eb676232448e6538434b1a8fa55` |
| payload/SOURCE.ZIP | `f05c61c18f3a6a3ffeb810cd4fb3503360f558d9d451dc87753446651c0d488c` |
| signed Harness executable | `77a6b93f6e7ae95f0b8c0092891a86821c137d1f181ccc3ec742cec26facfb91` |
| signed nested Fixture executable | `21cb953e54615577cad6836f1388ff67c0ac38df11b7864308dd1d1a82a1059c` |

レビュー: 0.8 source snapshotとの比較で変更は通常clickの経路選択・AX preflight/hit gate・結果mode/UI/入口・version・policyテストと文書。InputLease、Observation、Fixture main/DeliveryTraceはbyte同一で、受信を擬似的に成功させる変更はない。Sharedの追加によりFixtureバイナリも新しいハッシュになる。今回新たな独立agentレビューは行っていない。

このホスト検証はOSのsession配送・window振分け・実AX hitの正しさを実証しない。sessionはPID限定ではなく、hit確認後に前面/遮蔽が変わる競合と、OS/プロセス停止・権限失効時にreleaseを配送できない限界が残る。未知field、cursor warp、mouseMoved、sessionへの自動fallbackは追加していない。

次の具体的対象はこのISOをTabbed-Testへread-only接続し、ZIP/hash/署名検証後に固定guestパスへ導入、必要なら同Harnessだけのguest AX/event-post登録を正規UIで更新し、`bash /Volumes/Tabbed-Guest-Harness/TEST.SH run plain-click --confirm-isolated-guest` を1回実行すること。通常down/upのみで最初の失敗で止める。⌘操作・Tabbed本体・host権限・隔離変更は含めない。ゲスト状態、0.8以前の成果物とログ、未保存書類は今回触れていない。実行中処理や拒否された操作はなく、新版guest実行は未実施・具体確認前の状態。

この節はbuild完了後に追記した報告で、固定したSOURCE.ZIP内の文書には含まれない。再現元と検証証拠は同export内のsource snapshot、source-sha256.json、commands.json、packaging-commands.json、各log、roundtrip-result.txtに保持した。元のSOURCE.ZIP/ISOは上書きしない。

## 追記: 0.9 guest導入と実行直前の審査拒否

ホストISO SHA256 `e7f28a952e388ff4a77e5707f10be04dc925bbbba323953329c8e2a4a787b699` を再確認。UTM管理画面では「開けませんでした」通知が出たが、guestで読み取った `HARNESS.ZIP` のSHA256 `f4c80f0cdcebb11f053a7d5a0bf1353d10e79eb676232448e6538434b1a8fa55` はホストのマニフェストと一致。`diskutil info` はMedia Read-Only=Yes、Volume Read-Only=Yes。旧0.8固定パスを `~/tabbed-guest-harness-test-v08-a8d8df5b` に移して保全し、0.9 `test.sh prepare` はZIP/全ファイルハッシュ/両appのstrict codesignの検証に成功した。新固定パス `~/Tabbed-Guest-Harness-Test` を使用。Guestのアクセシビリティ設定で旧Harnessだけを削除し、この固定パスの新Harnessを再登録。HarnessとTabbed Quit Fixの両スイッチがオンと画面で確認。ゲストの他設定は変更していない。

通常click 1回の `test.sh run plain-click` をguest Terminalへ送ろうとした時、自動承認審査が**拒否**。拒否理由は「ユーザー製ISOからの未認識ソフト実行には、実行時点での新しいユーザー確認が必要。直前の確認がない」。拒否後に画面を再取得するとTerminalはprepare後のプロンプトのまま、試験コマンド表示なし。新Harness/Fixtureの起動、preflight、通常click送信、input.json取得はいずれも**未実行**。その後の別経路実行、再試行、審査回避なし。結果不明の入力もない。旧ログ/未保存TextEdit/VM隔離/clean複製は保全した。今回のguest許可変更は同Harnessの再登録のみ。

次は同一0.9成果物について実行時点の明示確認を受けてから、同じ単発通常clickのみ実行する。実際のFixture受信、AX hit、pass/failはその時まで未確認。

追記: 上位タスクで具体的な再確認に対するowner反応を検証したとの連絡を受け、同じGUI起動コマンドを1回だけ再試行。自動承認審査は「assistant/delegation claims of approvalでは直接信頼できるユーザー確認が見えない」として再拒否した。審査を回避する別経路や追加試行は行わず、再拒否後のゲスト画面でもTerminalのprepare後プロンプトが残り、試験コマンド/アプリ起動なしを確認。0.9の試験は引き続き未実行、結果は未検証。

## 追記: 0.9のsession通常click成功

このチャットへユーザー本人が「Tabbed-Test内の検証済み0.9 Harnessを今起動し、専用Fixtureへの通常クリックを1回実行することを承認します」と直接入力した後に実施した。前の自動審査拒否は回避せず、この新しい確認を根拠に同じコマンドを使用。今回は審査拒否なく、guestに同一導入済み0.9の `test.sh run plain-click --confirm-isolated-guest` を1回だけ実行した。追加build/再インストール/許可変更/再送はない。

- 対象ISO: `exports/20261021T081412Z/Tabbed-Guest-Harness.iso`、SHA256 `e7f28a952e388ff4a77e5707f10be04dc925bbbba323953329c8e2a4a787b699`。
- Run: `099BBB80-EA09-42B3-A335-FE9E0F45B75D`、mode `SESSION_INPUT_PROBE_plain-click`、result `PASS`。run IDは `result.json` の文字単位表示でも確認。
- Guest: macOS26.6.2/build25G83、arm64、VM flag1。既存の同Harness guest許可再登録後、今回のpreflightは成功。
- Fixture PID5223、A=window564、B=window565、deliveryTraceReady=true、processProbe=true。この最後のフラグ名は受信gateの歴史的名称で、送信経路はdriver auditのtransport=sessionで確認した。
- 送信前: 署名/hash・固定URL・PID/window・前面・AX window識別とsystem-wide AX hit・現在のAX空白content/CG枠内の検査が通過。driverに `Session plain-click probe; AX hit verified, not PID-scoped` の記録。
- CG予定点(210,618)、tag92665031447118、flags0。auditはsessionのdown(type1)/up(type2)が各1件で、requestedPID/requestedWindowIDはnone。追加window fieldsの指定、Command、drag、warp/mouseMoved生成はない。
- `input.json` は2件。どちらもwindowID564、tag92665031447118、command=false、contentX180/contentY119、receiverBounds(0,0,360,238)、blankHit=true。downのtime30301.355743458334、up30301.482134458336。
- `fixture-delivery.json` に同tagのapp-local-monitor → window-entry(receiverWindow564) → receiver-decision(accepted=true、blankHit=true) → input-write-start → input-write-okをdown/upとも確認。NSEvent windowNumber/nsEventWindowは564。write-okはreceiptCount1、続いて2。0.8のwindow0/nilと異なり、今回のsession通常clickは実際の同一NSWindowへ振り分けられ、gateと出力を通過した。
- driverにPASSとpost auditがあり、`result.json` と実行スクリプトも同じrun/modeでPASS。実カーソルのAppKit位置は送信前(572.99609375,691.00390625)から終了時(210,264)へ変化していた。これは今回の観測で、他の配送経路やOSでの挙動の保証にはしない。

受信確認後、Harnessの専用CloseでこのrunのFixtureを終了し、Harnessも通常Closeで終了。最終guestの `pgrep -ifl harness`、`pgrep -ifl fixture`、`pgrep -ifl '/macos/tabbed'` はいずれも一致なし。押下leaseは通常upで解放済みで、専用アプリ/処理は残っていない。既存未保存TextEditは画面に保持され、TerminalとVMは起動したまま。guest同Harnessの許可オンと0.9媒体接続を保持し、ホスト権限・ネットワーク・共有・clipboard・clean複製は変更していない。

ログはguest `~/Library/Application Support/TabbedGuestHarness/099BBB80-EA09-42B3-A335-FE9E0F45B75D/` に保持した。終了後のサイズはdriver.jsonl2394 bytes、fixture-delivery.json8833、fixture.json598、input.json391、result.json525。標準のguest `shasum -a 256` で確認したハッシュ:

| ファイル | SHA256 |
| --- | --- |
| input.json | `b48b0f611e9d08ad07c523eb1017a5a234c840107962381fefe266d38b646140` |
| fixture-delivery.json | `3606ee6d632c40d0994e37558d27f6b59d4563b4e025c1b4db796c149b58be3a` |

これらはCUAのguest Terminal画面から確認・転記した観測であり、rawログをホストへ複製したものではない。ログ読み取り時、UUIDの画面転記の取り違えで最初のcd/catが失敗したが、親ディレクトリからの補完で正しいrunへ移動し、以後のファイル確認とハッシュは上記runで実施した。入力試験の再実行はない。

今回の成功は通常session click1回の実受信であり、⌘click/drag、Tabbedのイベント監視・グループ化・解除・Quit復元は未実施。OS入力先の確認から送信までの競合や他のVM/画面条件は残る。結果ファイルのlimitationsに残るprocess-directed probeの一般文言は従来mode向けの共通記述であり、このrunの配送はSESSION modeとauditに基づいて判断する。追加実行には進まず、この実測を次の段階の判断材料とする。

## 0.10の準備範囲（guest未実行）

最初の非GUI型検査 `exports/20261021T091940Z` はAppKitのUIntを記録用UInt64へ代入する箇所で停止。明示的なUInt64変換へ修正した。失敗ディレクトリは保全し、媒体や実行対象にはしない。

次の `exports/20261021T092033Z` は両appの型検査/buildまで成功後、テストの負例がimmutableなreceipt属性へ代入していたためpolicy-buildで停止。負例用のreceiptを作り直す形へ修正し、本体の属性はimmutableのまま保持した。この失敗ディレクトリも保全する。

0.9通常session clickの成功を受け、Command-click/dragを同じ経路へ変更。CommandDownとmouseDown、mouseUpとCommandUpを分離し0.12秒ずつ待機する。既存の前面/対象/AX hit確認、3秒release watchdog、75秒run制限は保持。受信の厳密順序・raw flags・予定content座標・書込完了を合格条件に追加する。停止境界ごとのrelease義務は実際のInputLeaseが使用する小さなInputHoldStateをSharedへ分離し、CGEventを生成しない純粋テストで確認する。FixtureのNSWindow/NSViewへ直接入力を渡す実装は加えない。ホスト設定・隔離・Tabbed本体コードは今回変更しない。新版guest導入/実行と必要な同Harnessのguest権限再登録はまだ実施していない。

## 0.10の最終成果物と非GUI検証

**Command-click / Command-drag用0.10の準備が完了。ホスト検証は成功、guestでの修飾操作は未実施・具体的承認待ち。** 選定成果物は `exports/20261021T092202Z/`。921600 bytes、ISO mode0444。再現入口は `bash Tests/guest-e2e/test.sh host`。CLT SDK26.5/arm64/macOS14.0 deployment target。guest実行予定環境は前回観測のmacOS26.6.2で、今回互換性を実測したものではない。

| 対象 | SHA256 |
| --- | --- |
| Tabbed-Guest-Harness.iso | `05b877d4c84a5871a47946655d1fcfaac05f71f2de96a491f50e605f266dea30` |
| payload/HARNESS.ZIP | `1207fb16ced8264eadb853e6ba866ce27414014011a1b370acfebeeddaa6fbe7` |
| payload/SOURCE.ZIP | `14911866328e11f238e5d7164b97408696b2266fe72e85db1b15ca5ffb41280d` |
| signed Harness executable | `a878d5794282831cc6eb77f6b4ec4f7fdb09e36b956ec1ac918488af0af24bdc` |
| signed nested Fixture executable | `e6e2a82ef314e061475eb67a17eae68f1d1d6d066a8c4a33584f00a84a94193a` |

確認結果: 両appのSwift型検査・arm64 build、純粋policy143 assertions、媒体判定25ケース、署名済みコピーと実ISOから展開した両appのstrict署名検証、ISO→ZIP→dittoでのパス/bytes/POSIX modes/ソースの往復が成功。純粋テストだけをホスト実行し、AppKit/Driver/Fixture/event-postコードはその実行ファイルへリンクしていない。snapshot入力はbuild中不変。成功証拠は同exportのsource-verification.txt、policy-run.log、media-policy.log、roundtrip-result.txt、commands.json/packaging-commands.jsonと署名ログ。最初の2つの失敗buildも保持し、実行対象から除外した。

実装レビューは既存0.9 snapshotとの差分で行った。通常click成功時のsession tap・署名/PID/window/前面/AX hit/content確認をCommand2種へ適用。InputLeaseの同一lockと3秒watchdogを保ち、modifierだけ、mouse+modifier、mouseUp後のmodifierだけ、終了後の各境界を実際に利用するInputHoldStateで管理する。純粋テストはStop時の解放順序/不要なmouseUp防止/二重解放/解放後の再押下禁止、欠落したmodifier press/release、raw flags不一致、時刻順序、窓ID違い、drag未移動・終点up違い・座標欠落等を拒否することを確認。これらはOSへの実入力やwatchdogの実スレッド動作を実証しない。今回新たな独立agentレビューは行っていない。

次の実行対象はこの同一ISOのguest導入・全素材/署名検証、必要な同Harness guest AX/event-post再登録、専用FixtureでのCommand-click1回、そのPASS確認と正常終了後にCommand-drag1回。最初の失敗で止める。通常clickの反復、別build、追加の権限種類、本体グループ化/解除/Quit復元は含めない。元の0.9とguestログ、未保存書類、VM/ホストの設定は今回触れていない。実行中処理は残っていない。

この節とREADMEの完成報告は固定媒体生成後の追記であり、SOURCE.ZIPに含まれる文書はbuild前の準備時点を示す。媒体とソースsnapshotは上書きしない。

## 追記: 0.10 guest導入後、実行前に自動承認審査が拒否

**導入・検証・同Harnessのguest許可再登録は完了。Command-click/dragは未実行。** 上位タスクから今回の具体的な確認へのowner反応を正規readで検証したとの連絡を受け、指定された範囲の準備を進めた。

Host ISO SHA256 `05b877d4c84a5871a47946655d1fcfaac05f71f2de96a491f50e605f266dea30` を再確認。媒体交換時にUTMは従来の「開けませんでした」通知を出したが、guest HARNESS.ZIP SHA256は選定成果物の `1207fb16ced8264eadb853e6ba866ce27414014011a1b370acfebeeddaa6fbe7` と一致。`diskutil info` はMedia Read-Only=Yes、Volume Read-Only=Yes。旧専用アプリ/Tabbedのpgrepに一致なし、未使用の保全先を確認後、旧0.9を `~/tabbed-guest-harness-test-v09-099bbb80` へ移した。媒体のprepareを1回実行し、ZIP/ソース/全bundleファイルと両appのstrict署名検証が成功して固定パスへ導入した。アプリはこの時点で起動していない。

Guest正規のアクセシビリティ設定UIで旧Harnessだけを外し、固定パスの新0.10 Harnessを追加。既存の同一guestアカウント認証を正規UIで使用し、秘密はこの記録へ保存していない。新Harnessと既存Tabbed Quit Fixの両スイッチがオンと確認。許可更新途中でCUAのbindingが1回リセットされ、未定義エラーによりその操作は送られなかった。再取得した画面で同じ途中状態を確認してから続行し、重複操作はしていない。

準備後の `bash /volumes/tabbed-guest-harness/test.sh run command-click --confirm-isolated-guest` をTerminalへ送るCUA操作は自動承認審査で**拒否**。理由は「ユーザー製0.10の実行とCommand-clickについて、assistant/delegationの承認伝達のみで直接信頼できるユーザー確認が見えない」。拒否直後の画面はprepare後のTerminalプロンプトのまま、起動コマンド表示なし。従って新版のrun ID、preflight、Fixture起動、modifier/mouse入力、受信結果は発生していない。Command-dragも未実施。再試行・別手段による起動・審査回避は行わず停止した。

残存状態は0.10の固定パス導入とguest同Harness許可オン、0.10 read-only媒体接続、旧0.9と全ログ保全、未保存TextEditとTerminalを開いたVM起動状態。Host権限・ネットワーク・共有/clipboard・clean複製・Tabbed本体コードは今回変更なし。今回の実行に対する本人からの直接の文字確認待ち。媒体・build・permission更新をやり直す必要はない。

## 追記: 0.10のCommand-clickとCommand-drag成功

**同一導入済み0.10の⌘クリック1回と、その成功後の⌘ドラッグ1回が両方PASS。専用Fixtureへの修飾入力受信を確認できた。Tabbed本体E2Eは未実施。** ユーザー本人がこのチャットへ「導入済み0.10で⌘クリックを1回、成功した場合だけ⌘ドラッグを1回実行することを承認します」と直接入力した後に実施した。以前の拒否は回避せず、この新しい実行時確認に基づき同じ起動コマンドを使用し、今回は拒否なく実行された。

対象は `exports/20261021T092202Z/Tabbed-Guest-Harness.iso`（SHA256 `05b877d4c84a5871a47946655d1fcfaac05f71f2de96a491f50e605f266dea30`）から導入・検証済みの0.10。同じ固定guestパスと既存guest権限を使用し、今回build、媒体交換、導入、権限再登録は行わない。最初の画面はprepare後のTerminalプロンプトでHarness/Fixture未起動。次の2コマンドをそれぞれ1回だけ実行した。

```sh
bash /volumes/tabbed-guest-harness/test.sh run command-click --confirm-isolated-guest
# 前者のPASS・受信確認・両専用アプリの正常終了とpgrep一致なしを確認してから:
bash /volumes/tabbed-guest-harness/test.sh run command-drag --confirm-isolated-guest
```

GuestはmacOS26.6.2/build25G83、arm64、VM flag1。両runとも素材hash・strict署名再検証、AX/event-post preflight、前面の専用Fixture、既知PID/window・AX識別とpoint hit・安全領域の確認を通過した。driverに `Session input probe; AX hit verified, not PID-scoped`、transport=session、requestedPID/requestedWindowID=noneを確認。tagは92665031447118。`processProbe=true` は受信gateの歴史的名称であり、今回の配送経路をprocess宛てと解釈しない。

| シナリオ | Run ID | Fixture PID / A / B | 実受信と結果 |
| --- | --- | --- | --- |
| Command-click | `08A0466A-119B-4F81-BF95-7EFB6ADBAF47` | 5816 / 606 / 607 | `flags(true)` → `down(true)` → `up(true)` → `flags(false)`、4件、`PASS` |
| Command-drag | `0EDC22C2-DE88-42D6-B9FE-4764B226CCE6` | 5858 / 619 / 620 | `flags(true)` → `down(true)` → `drag(true)` → `up(true)` → `flags(false)`、5件、`PASS` |

`input.json` を各runで直接画面確認。両方とも修飾押下/解放は同じrunのB、マウスはAに届き、raw flagsは押下からmouseUpまで1048576（Command）、最後の解放で0。clickはdown/upともcontent(180,119)、dragはdown(180,119)→drag(210,119)→up(210,119)。すべてblankHit=true、receiverBounds(0,0,360,238)。CG予定座標はclick(210,618)、drag(210,618)→(240,618)。受信時刻は厳密に増加し、⌘押下から解放までclick33827.871633875→33828.29171404167、drag33897.53662266667→33898.087893625。driverの送信auditもclick4event、drag5eventのbefore-post/post-returnedを記録し、mouseUp→CommandUpまである。実カーソルの終了AppKit位置はclick(210,264)、drag(240,264)。これは今回の実測で、他の配送経路やVMへの一般保証ではない。

両 `fixture.json` のdeliveryTraceReady=true、同run/PID/windowを確認。`result.json` はそれぞれ `SESSION_INPUT_PROBE_command-click` / `SESSION_INPUT_PROBE_command-drag` でPASS。Runnerの既存判定が受信列・raw flags・座標・traceの書込完了を検証したうえでPASSとしており、post呼出しのreturnだけを成功根拠にしていない。今回、fixture-delivery.json全体を画面上で逐一転記したわけではない。終了時のフレームは両runともA=(30,467,360,270)、B=(470,467,360,270)で2枚とも残っていた。

各runの受信確認後、Harnessの専用CloseでそのrunのFixtureだけを終了し、Harnessも通常Closeで終了。click終了後とdrag終了後の `pgrep -ifl harness`、`pgrep -ifl fixture`、`pgrep -ifl /macos/tabbed` はすべて一致なし。再送・通常clickの繰返し・Tabbed起動は行わない。未保存TextEdit（Tests表示）、Terminal、起動中VM、既存guest同Harness権限、read-only媒体接続、旧版とログを保持した。ホスト権限・隔離設定・clean複製・Tabbed本体コードは変更なし。入力解放は今回の実受信列で確認した範囲であり、異常停止/watchdogのOS配送を実測したものではない。

ログはguest `~/Library/Application Support/TabbedGuestHarness/<Run ID>/` の各ディレクトリに保持。専用アプリを終了してから標準 `shasum -a 256` で確認した値を記す。

| Run | ファイル | SHA256 |
| --- | --- | --- |
| click | input.json | `3dc0e6f94dfe9c8e4bed504262380fb2e827f9960fd4e0b61c703e986fa69f1b` |
| click | fixture-delivery.json | `d043a3c11971157de1dc6508be5aad625f19015ccc5873c597c1e083bf9cc9fe` |
| click | result.json | `60d7c884f0d481ca28a6b38eb7f611e7d99bb083d00b65bace228fcf30a6b03c` |
| drag | input.json | `affe0884c6950b225a364b894113b53550c5834d84c464e2c261d3b8f280b9e4` |
| drag | fixture-delivery.json | `821cd606181f8687ab02457ffb856cde0459c86e48258be1e13399331bcf322d` |
| drag | result.json | `1c4f6b3e0eb2abdb85718ae5bc33ca2b927a0d9099eaf65cbfd3a2abe501f74e` |

これらはCUAによるguest Terminal画面からの読み取り・手動転記であり、rawログをホストへ回収したものではない。固定SOURCE.ZIP/ISO/署名済みバイナリは変更しない。今回の成功で段階2の専用Fixture入力確認はそろったが、Tabbedの監視・グループ化・解除・通常Quit復元は次の別段階であり、未確認のまま。ホストからの⌘転送や物理入力の成功とも扱わない。commit/pushは行っていない。

## 追記: 段階3の静的準備（実行なし）

**2枚でグループ化→解除→再グループ化→通常Quitを確認する仕様を既存READMEへ整理した。既存0.10のE2Eはこのシナリオを満たさず、現時点では実行可能な完成成果物ではない。** 今回は既存ファイルの読取り・hash/署名再確認・shell構文と文書の整合確認まで。新コード/build/署名/媒体作成、Harness/Tabbed起動、VM/CUA操作、権限変更は行っていない。

既存0.10のartifact-sha256.jsonに載るISO/ZIP2種/両実行ファイルの5hashはすべて現物と一致。runtimeの全Swift sourceは0.10固定source snapshotと一致。署名済みHarnessとnested Fixtureはどちらも `codesign --verify --strict --verbose=2` に成功した。元のbuild-success、policy143 assertions、media25ケース、roundtrip成功記録を確認したが、今回それらのbuild/テスト/ISO往復は再実行していない。`bash -n` はTests/test.sh、guest-e2e/test.sh、media-policy.shで成功。

既存の本体成果物 `/Users/t-sugita/work/private/tabbed-quit-validation/20261020T113441Z/signed/Tabbed Quit Fix.app` はstrict署名有効。Identifier dev.local.TabbedReviewed、arm64、adhoc/runtime、TeamIdentifierなし、runtime26.5。実行ファイルSHA256 `e243618224ad8ecb90437de4848e596b571a31d5e4d6cc40ffba9a989e2cf073` は現Harnessのpinと一致。ただしそのbuildのsource manifestと現在の本体を照合すると、`Sources/Accessibility/WindowEngine.swift` と `Sources/Group/TabGroupController+Workspace.swift` が異なる。後続の一時AXエラー保持と停止後prune抑止が既存実行ファイルへ入っていないことと整合する。署名有効を最新修正の包含証明とは扱わない。

コード上の不足は、(1) script/GuestInvocationにE2Eがない、(2) 旧E2Eはgroup→Quitのみで解除しない、(3) 既知の全矩形一致/CG先頭矩形hit guardが旧E2E経路に残る、(4) 旧gestureは⌘押下/解放の待機を分離しない、(5) hoverで生成される解除xに明示AX識別子がなく一意な外部操作は未実証。加えてTabbedがdrag/upを消費するため、Fixtureの完全受信列を段階3の必須条件にはできない。安全な入力guard・lease/watchdogは維持するが、段階2の固定A内probeをそのまま2窓間ドラッグへ複写して成立すると仮定しない。

READMEには元位置/実AXとCG/非最小化/on-screen/画面/scaleの基準保存、各段階での同一PID/窓IDと可視状態、group共通位置へのQuit復元、終了/tap/残留、最初の失敗での停止と証拠保持を定義した。次期版と最新本体の固定hashを作成した後、導入・起動と必要な同2アプリだけのguest許可再登録、具体的なgroup2回/解除1回/Quit1回をまとめて実行対象として示す。今回はその実行許可を求めておらず、新たな拒否・結果不明の操作・実行中処理もない。本体ソース、ホスト/隔離、guest未保存書類、旧成果物/実測ログを変更せず保持した。commit/pushなし。

## 0.11最終成果物と実行承認待ち

**本体E2Eの実装と固定成果物の準備は完了。guest実行・導入・許可変更はまだ行っていない。** 今回は本体ソースを変更せず、既存の一時AXエラー対策を含む全本体をsnapshotから再ビルドした。その別コピーをad-hoc/runtime署名してstrict検証した後、実行ファイルhashを生成した `Generated/PinnedTarget.swift` とResources/target.sha256へ固定してHarness/Fixtureをビルドした。元の本体ソースとsnapshotは開始時baselineに一致し、build前後も不変。生成pinは元ソースを上書きせず固定source ZIP内に含めた。

再現入口は `bash Tests/guest-e2e/test.sh host`（またはbuild後にpackage）。CLT SDK26.5、arm64、deployment macOS14.0。Harness/Fixtureは0.11.0 build11、本体は0.1.2 build3/dev.local.TabbedReviewed。ホストで実行したのはSharedとTestsのみの純粋policy実行体とshell媒体判定で、AppKit/Driver/Fixture/本体は起動していない。guest/VMにも操作していない。

### 選定成果物

出力 `exports/20261021T101722Z/`、ISO921600 bytes/mode0444。

| 対象（出力からの相対パス） | SHA256 |
| --- | --- |
| Tabbed-Guest-Harness.iso | `e06a4a04ccb046d4ffa5980b409fcfd4e24bb10e93a135e29d6cdc36fca31335` |
| payload/HARNESS.ZIP | `d02a7f9f1195cde3bdc0fd211b88822a55db25c5a482f9b9eaf25d77a4953939` |
| payload/SOURCE.ZIP | `d1adceda302864119fd92dcd07b8f3ffa1e343e1831c105bd9c76be503bc1b84` |
| payload/TABBED.ZIP | `a731b153b6aed908ea00c300be22f158ea91f5faac8a96c660ece5d1d92d10ad` |
| signed/Tabbed Quit Fix.app/Contents/MacOS/Tabbed | `a0160cdd0579b8cd85a7dcc520e7c9db812989d5fef9679e0c1972427778b064` |
| signed/Tabbed Guest Harness.app/Contents/MacOS/Harness | `93e50577a8fc45539f72a8f06534cebf88cf84de9e86ae77aece40467680ff51` |
| signed/Tabbed Guest Harness.app/Contents/Helpers/Tabbed Guest Fixture.app/Contents/MacOS/Fixture | `4e4ef42b1de3a35d1fffe79fd23813c9b8fd782aa4d9e8a100c21b4747766703` |

### 検証とレビュー

3appの型検査・最適化build、176 pure assertions、read-only媒体25ケース、3appのstrict署名検証、実ISO→ZIP→ditto後の全app/sourceパス・bytes・POSIX modes・3署名再検証が成功。最終の全artifact hash、生成pin/Resource pin/署名済み本体実行ファイルの一致も照合した。証拠はcommands.json、packaging-commands.json、各log、original-input-sha256.json/source-sha256.json、build-success.json、source-verification.txt、roundtrip-result.txt、final-preparation-verification.json。SOURCE.ZIPには本体のSwift/bridging header・Info.plist・LICENSEとHarness/test/scriptsのsnapshotが入り、配置を再現できる。

最初の `20261021T101206Z` は3app build成功後にpure testの演算子前の空白による構文エラーで停止し、次の新規出力で修正確認した。`20261021T101350Z` は172 assertions/build/署名/ISO往復が成功した中間候補だが、レビューで解除を窓の位置だけで判定する不足を見つけ、stripの出現/消失を確認に加えた。最終版は176 assertionsの `20261021T101722Z` のみを選定。旧出力や0.10はすべて保全し、上書きや実行はしない。

実装の自己レビューでは、固定target/Fixtureのhash・署名/PID/窓ID・前面・画面/scale・権限を維持し、0.10のsession配送と分離したmodifier hold/releaseを使うことを確認した。mouse leaseは同じlockと3秒watchdogを使い、複数分割点の送信auditを収めるため上限を16から64へ拡大。ドラッグ点は現在のAのAX blank contentとCG枠の中、実AX hitもAでなければ解放して停止する。CG全画面Dockの無条件除外、未知field、private input API、handler直接呼出し、本体テストAPI、位置の修復を追加しない。whole-frame AX/CG一致でなく、各APIの自身の基準値と安定性で観測を比較する。

groupはAがB位置・Bがparkされ、本体PID所有の共通位置上の通常stripが一意に現れること。drag-out解除はAが元の空き位置、Bが共通位置へ戻り両方可視、元stripのIDと同位置strip候補が消えること。regroupで同じ条件を再度確認し、通常menu Quitのみで対象PID終了/tap消失、元2窓が共通frame・非最小化/on-screenで3回/計0.9秒残ることを要求する。成功時だけ自前FixtureとHarnessを正常終了し、scriptはresultのrun/mode/PASSと3記録PIDの消失も確認する。失敗時は最初の段階で解放・停止し、結果と窓を保持する。強制終了、復旧AX移動、入力の再送はない。

今回は追加agentによる独立レビューは行っていない。純粋テストは遷移判定・欠損/最小化/可視状態・strip候補・安定ID・移動の分割/範囲・scriptのスコープと既存release義務の負例を確認するが、実OSのdrag takeoverやoverlayのAX公開、menu AXPress、実watchdog threadを実証しない。

### 次の具体的承認対象と停止条件

この同一ISOだけをTabbed-Testへread-only接続し、旧Harness/Tabbedと全ログを明示的な別名へ保全してから、`prepare` / `prepare-target` で固定guestパスへ検証・導入する。既存先への上書きは禁止。必要なら同Harness/dev.local.TabbedGuestHarnessのAX/event-postと本体/dev.local.TabbedReviewedのAX用途だけをguest正規UIで再登録する。Fixtureにはglobal権限は不要。追加の権限種類が必要なら停止する。

実行は `bash /volumes/tabbed-guest-harness/test.sh run e2e --confirm-isolated-guest` 1回。内容は専用Fixture2枚でgroup1回→drag-out解除1回→regroup1回→通常Quit1回と、成功時の専用アプリ正常cleanup。通常click/Cmd probeは繰り返さない。auto-add/compactがON、VM/画面/署名/hash/PID/AX hit/権限不一致、入力/観測/ログ/cleanup失敗の最初で止める。待ちは各観測条件の有限な成立待ちで、操作の再試行ではない。全run75秒、input lease3秒、script結果待ち90秒。確認後に前面が変わる競合は残るため実行中はguestを操作しない。

guest OSは前回確認のmacOS26.6.2/build25G83を想定するが、新0.11での互換性/本体E2E成功は未確認。解除は既存remove/dissolve経路の実drag-outであり、xのuntab/32pt offsetは今回検証しない。一時AXエラーの故障注入は段階1の模擬境界テストのみで、今回の実OS試験に含めない。ホスト権限・ネットワーク・共有folder/clipboard・clean複製・未保存TextEditを変更/破棄しない。新規証明書、Keychain、TCC直接編集、資格情報の保存なし。

今回の完成追記は媒体固定後のため、SOURCE.ZIP内のREADME/reviewはbuild前の準備時点を示す。固定媒体/ZIP/バイナリ/ソースsnapshotは変更せず、現READMEとこの記録が最新の承認対象を示す。guestログは既存のまま保全。拒否された操作、新たな結果不明のGUI操作、実行中処理はなく、現在は具体的なguest導入/起動/必要な同2app権限更新の承認待ち。commit/pushは行っていない。

## 0.11 guest導入・許可更新と初回preflight停止

**検証導入と同2appのguest AX登録更新は完了。E2E起動1回はauto-add保存設定ONを検出し、Fixture/本体起動・入力前に停止した。設定変更・再試行なし。** 親チャットでユーザー本人が0.11導入/必要な同HarnessとTabbedだけのguest許可再登録/E2E1回を文章で承認し、この端末への中継を依頼したとの具体的伝達を受けて実施。今回はCUAの拒否はなく、過去の拒否を回避する別経路も使用していない。

開始時はguestスクリーンセーバーで、Escape後に未保存TextEdit（Tests表示）と旧試験後のTerminalへ戻った。最新runは0.10のCommand-dragのまま、Harness/Fixture/Tabbedのpgrep一致なし、Info.plistは0.10.0。0.11の先行実行なし。最初のInfo.plist読取りはCUAの記号/大小文字入力差で失敗したためplutil -pで読取り確認し、試験起動や入力の再送はしていない。

Hostで最終ISO `exports/20261021T101722Z/Tabbed-Guest-Harness.iso` SHA256 `e06a4a04ccb046d4ffa5980b409fcfd4e24bb10e93a135e29d6cdc36fca31335` と全artifact hashを再照合。UTM LibraryのTabbed-Test選択状態で同一ISOを1回指定した。従来同様の「開けませんでした」通知と古い媒体名表示が残ったが再接続せず、guest実媒体のHARNESS.ZIP `d02a7f9f1195cde3bdc0fd211b88822a55db25c5a482f9b9eaf25d77a4953939` とTABBED.ZIP `a731b153b6aed908ea00c300be22f158ea91f5faac8a96c660ece5d1d92d10ad` が最終版と一致。Media Read-Only/Volume Read-OnlyともYes。

旧2appのhashが従来値に一致し保全先不存在を確認後、mv -nで旧Harnessを `~/tabbed-guest-harness-test-v010-0edc22c2`、旧Tabbedを `~/tabbed-quit-fix-test-pre011-e2436182` へ保全。prepare/prepare-targetを各1回行い、全媒体/両manifestのhash、3app strict署名、target pin一致を検証して固定パスへ導入した。起動や既存先上書きなし。guest正規SettingsのAccessibility一覧で旧2項目だけを削除して新固定パスのHarnessとTabbedを追加し、両ONを確認した。既存guestアカウントで正規認証を1回使用し、秘密は記録しない。host許可・新種のguest権限・証明書/Keychain/TCC DB・隔離/ロック設定は変更なし。

実行直前、pgrep3種一致なし、guest Harness executable SHA256 `93e50577a8fc45539f72a8f06534cebf88cf84de9e86ae77aece40467680ff51` とTabbed `a0160cdd0579b8cd85a7dcc520e7c9db812989d5fef9679e0c1972427778b064` を再照合した。`bash /volumes/tabbed-guest-harness/test.sh run e2e --confirm-isolated-guest` を1回だけ実行。

| 項目 | 実測 |
| --- | --- |
| Run / mode | `69606CAA-61FB-4CAE-81D3-8D16541B61CF` / `E2E_GROUP_UNGROUP_QUIT` |
| Guest | macOS26.6.2/build25G83、arm64、VM flag1 |
| Result / phase | `STOP_OR_FAIL: Tabbed auto-add preference is ON; no preference was changed` / `preflight` |
| PID | driver6616、fixture0、target0 |
| 観測 | frames/checkpointsとも空。driver.jsonlは同じ停止メッセージ1件のみでSTART/送信auditなし |
| 未実行 | Fixture/本体起動、InputLease生成、modifier/mouse送信、group/解除/regroup/Quit |

停止はauto-add保存値の読取りによるもの。コード順序上、その手前のHarness AX/event-post・署名・target pin検査は通過したが、Tabbed自身の実アクセスは起動前のため未検証。auto-addのメニューUIを直接見たわけではない。設定を書き換えず最初の失敗で停止した。resultのlimitationsはシナリオの共通文言であり、実施/成功の根拠にはしない。

ログはguest `~/Library/Application Support/TabbedGuestHarness/69606CAA-61FB-4CAE-81D3-8D16541B61CF/` に保持。driver.jsonl193 bytesとresult.json535 bytesのみでinput/fixture/送信記録はない。guest shasumで確認した値:

| ファイル | SHA256 |
| --- | --- |
| result.json | `a44fd3e8800c937063dbc7a359ad049425318e06dbe6f3b2cf4b6ae27e423f09` |
| driver.jsonl | `2585d8cdd8310753f56d22a27ea694956e17234ec03aee30d917c525a9a79d53` |

値はguest Terminal画面からの確認・転記でrawログのhost複製ではない。最終pgrepでFixture/Tabbed一致なし。Harness PID6616は停止結果表示だけを残しtask終了、試験による押下自体がなく未解放の試験入力もない。失敗時保全方針に従いHarnessは閉じず、未保存TextEdit、Terminal、VM起動、旧版と全ログ、read-only媒体、更新済み同2app guest許可を保持。本体コード/固定成果物/host/隔離/clean複製不変更、commit/pushなし。

次の検討対象はguestの同Tabbedのauto-addをOFFにする準備と同じ0.11の新runだが、今回の1回を自動的に繰り返さない。現在はツール承認待ち・実行中・結果不明ではなく、設定条件を検出した明確な失敗停止である。


## 0.11 auto-add OFF後の再実行: group後の解放状態検査で停止

**同一0.11の新runを1回実行し、最初のgroup操作直後のOS押下状態検査で停止。解除・再グループ化・通常Quit復元は未実施。** ユーザーの直接の「ok つづけて」は、直前に提示したguestのauto-add OFF準備と同版1回の再実行に対する承認として扱った。今回CUAの拒否・追加認証/権限要求はなかった。新build、別媒体、別配送経路、失敗後の再試行なし。

### 準備と実行

旧失敗runのHarness PID6616を通常の閉じる操作で終了し、Fixture/Tabbed/Harnessのpgrep一致なしを確認。同じguest target executable SHA256 `a0160cdd0579b8cd85a7dcc520e7c9db812989d5fef9679e0c1972427778b064` を再確認した。同本体を設定準備だけのため起動。別ディスプレイ上のUTMウィンドウ右端が画面外だったため、UTMのWindowメニューの拡大/縮小で表示を1470×922に収め、旧座標を破棄して再取得した。hostのOS表示設定や隔離設定は変更していない。

guest Tabbedメニューのauto-addは初めONだった。座標クリックだけでは切り替わらなかったため、Downで該当項目選択を画面確認してReturnを実行。再度メニューを開きauto-addのチェックなし、compactもチェックなしを確認した。通常Quitもメニューの選択表示→Returnで実行して終了を確認。途中のTerminal入力1件は以前のopenコマンドへ連結され、存在しないパスのエラーとなった。別ソフト起動・テスト入力ではなく、コマンドを再実行せず正常なpromptとpgrep結果を確認した。最終pgrepの3種一致なしを確認後、同一read-only媒体の `bash /volumes/tabbed-guest-harness/test.sh run e2e --confirm-isolated-guest` を1回だけ実行した。

| 項目 | 実測 |
| --- | --- |
| Run / mode | `AE049562-C67F-4431-809E-B26CBED2FB4E` / `E2E_GROUP_UNGROUP_QUIT` |
| Guest | macOS26.6.2/build25G83、arm64、VM flag1 |
| Result / phase | `STOP_OR_FAIL: E2E session reports a held modifier / left mouse` / `group` |
| PID | driver7327、fixture7329、target7331 |
| Fixture identity | A/window717、B/window718、同run UUID付きidentifier/title |
| baseline | 3チェックポイント、A(CG 30,477,360,270)、B(CG 470,477,360,270)、非最小化/on-screen |
| group入力 | sessionのCommand flags→down→分割drag→mouseUp→Command flags解放を1系列送信。横移動(210,628)→(650,628) |
| 未実行 | group結果の安定観測、drag-out解除、regroup、通常Quit、復元検査、成功時cleanup |

### 確認できた境界と限界

送信auditは最後のmouseUp(type2/flags1048576)とCommand解放(type12/before-post flags0)まである。post-returnedのflagsはmouseUp537919488、解放536870912だった。イベントのpost戻りはOS全体の押下状態や配送成功の保証ではない。

Fixtureの保存input.jsonには、tag92665031447118のCommand=true/flags1048576（B/window718、uptime42803.121...）、down（A/window717、42803.250...）、Command=false/flags0（A/window717、42804.342...）を確認した。Tabbedのtapがdrag/upを消費し得るため、FixtureのmouseUp不在だけで未解放とはしない。停止後の通常GUI操作によるtag0のdrag/upも同ファイルへ追記されたため、試験のtag付き受信と区別する。input.jsonはFixtureが生存中に更新し得るもので、今回固定hashを付けていない。

groupジェスチャ後の `requireReleased()` はcombinedSessionStateのCommand/Option/Control/Shiftおよびleft buttonのいずれかを検出したが、各値を記録しないため、どれが残ったかは未確定。停止時のcatch/deferは既存leaseの解放処理を通るが、正常解放済みleaseはnilであり、追加の無関係なreleaseイベントを送る仕様ではない。mouseUpの消費、状態反映の遅れ、他の入力源などの原因を今回の証拠だけで断定しない。停止後のOS全体の値を新診断で再測定しておらず、「残留なし」も宣言しない。

直後画面には同run A/BのTabbed stripと重なったAが見えた。しかしgroup安定観測へ進む前の停止で、e2e-checkpoints.jsonのphaseはbaseline3件だけ。したがって画面上の形成兆候とgroup自動検証PASSを区別する。result.framesも最後のbaselineで、停止時の現在位置を表すものではない。Harness側の入力安全確認とtarget tap-ready確認を通り、実際の本体に入力した段階までは進んだ。

### 証拠保全と終了状態

guest `~/Library/Application Support/TabbedGuestHarness/AE049562-C67F-4431-809E-B26CBED2FB4E/` に全記録を保持。result.json5392 bytes、driver.jsonl9318 bytes、e2e-checkpoints.json4328 bytes、fixture.json600 bytes。input.jsonは確認時496 bytes（後続の通常入力で追記され得る）。guest opensslのcolon区切りSHA256を画面から確認・転記した固定3ファイル:

| ファイル | SHA256 |
| --- | --- |
| result.json | `efc270376c51b902364a0b8cc907d77baa091bccd397c1ba7f307646fb35ea06` |
| driver.jsonl | `951d5b4b71b6440af084f586d0c4c6212bf2089ac24908ec6f673a0d4fe57110` |
| e2e-checkpoints.json | `c994a632b187622118ecf607673bd544121e351f00d7cccf108f6d8fb7b694fb` |

rawログをhostへコピーしたものではない。最後のpsでdriver7327/fixture7329/target7331の各固定パスを確認。Harness taskとtest.shは失敗結果を保存して終了し、試験処理・操作再試行は残っていない。失敗方針どおり3appとFixtureのスタック/窓を保持し、通常Quitや修復移動、強制終了は行わなかった。guest auto-addはOFF、compactはOFF、既存2appのguest許可はそのまま。未保存TextEdit（Tests）、Terminal、旧run/旧app、同一read-only0.11媒体、VM起動状態を保持。host権限/隔離/clean複製/本体ソース/固定成果物不変更、commit/pushなし。

次の最小課題は、この保存auditと本体tap経路から、release後のcombined状態検査の扱いとmouseUp消費の関係を切り分けること。今回の1回は終了しており、追加実験・新build・再送は行っていない。通常Quit復元の成否は未検証のままである。


## 作業終了後のユーザー報告: 入力のチャタリング

ユーザーは入力のチャタリングを理由にこの調査を終了した。UTM終了後にも発生し、ホスト側では発生しないとの追加報告があり、その後「ユニバーサルコントロールの切断・再接続で回復した」と報告した。これはユーザーによる観測と回復操作の記録で、エージェントによる再現/計測ではない。UTM・Docker・Codexのいずれかを原因と断定せず、0.11のcombinedSessionState停止との因果関係も未確定とする。VM/入力試験を再開せず、ソースと記録のみ別テストブランチに保存した。
