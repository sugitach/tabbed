# 起動直後のAX/WindowServer座標差と0.3修正

## 実測と静的判断

0.2のrun `4F5E5841-CF6C-450C-AAAC-8D455EF0EAFD` は権限再登録後にAX/event-post事前検査を通過し、STARTから約0.162秒後の最初の座標照合で停止した。AX=(30,785,360,270)、CG=(34,788,352,264)。中心は両方(210,920)、幅・高さの比は約97.78%。入力は未送信だった。生ログはゲストに保全し、ホストの[実測記録](guest-smoke-v02-result-20261021.md)は画面で確認した転記。

FixtureはmakeKeyAndOrderFrontの直後にhandshakeを書き、Driverはhandshake取得直後、既存の0.4秒activation待ちより前にobserveしていた。AppKitが表示開始する時点とAX/WindowServerの別々の読み取りの間に同期保証はない。この早い観測で同中心の縮小が見えたため、orderFrontアニメーションや表示更新の時差が有力な調査候補。ただし後続サンプルが旧ログにないため、収束や因果関係は実証されていない。

枠とコンテンツの違い、OS版による見た目の差も候補だが、一定の枠差であるとの証拠もない。Y軸反転やRetinaの2倍換算だけでは、この小さな同中心・同倍率差を説明しにくい。PIDとwindowIDは既存照合済みだが、それだけでAPI間の同時性は保証できない。

## Apple公式仕様で確認した範囲

SDK26.5の公式ヘッダーを読み、公開Web文書も照会した。Web文書はJavaScript必須／Markdown取得エラーとなり本文を取得できなかった箇所があり、その箇所の根拠は同SDK内ヘッダーとする。

- `CoreGraphics.framework/Headers/CGWindow.h`: kCGWindowBoundsはメイン画面の左上を原点とするscreen spaceのウィンドウ境界。コンテンツだけの領域との定義ではない。[API参照](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds)
- `HIServices.framework/Headers/AXAttributeConstants.h`: kAXPositionは要素左上のglobal screen位置、kAXSizeは要素寸法。
- `HIServices.framework/Headers/AXUIElement.h`: AXUIElementCopyElementAtPositionは左上基準のscreen座標でz-orderに基づくhit testを行う。system-wide AX要素を使うと特定アプリに限定されない。
- `AppKit.framework/Headers/NSWindow.h`: animationBehaviorはウィンドウ単位のorderFront/orderOut自動アニメーションを制御し、noneでAppKitの推定アニメーションを抑制できる。[API参照](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.property)
- [Quartz Display Services公式概要](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/Overview.html)もメイン画面の原点とglobal display座標を説明する。

ヘッダーの基点は `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/Library/Frameworks`。HIServicesはApplicationServices.framework/Frameworks配下。これらの仕様には、生成直後のAXとCGが同時に同じ矩形へ収束するとの保証は見つからなかった。

## 0.3で用意した最小の検証経路

1. Fixtureの2ウィンドウだけにanimationBehavior=noneを指定する。OS・他アプリの設定を変えない。抑制設定自体を収束の証明には使わない。
2. 起動後とactivation後に限り最大4秒・25回の待機を設け、各回のPID/windowID/AX identifier/title/role/subroleとバンドルパスを確認する。対象不在・識別不一致・無効矩形・AXエラーは即停止し、再取得によって別対象へ置き換えない。
3. AXとCGの既存許容差は各成分3ポイントを維持する。一致したサンプルが3回以上、0.3秒以上続き、最初のサンプルからAX/CGそれぞれの各成分が0.5ポイント以内に収まることを要求する。隣接サンプルだけで比較せず、緩やかなドリフトも許さない。不一致では安定履歴をリセットする。永続不一致はtimeoutで停止する。
4. 単一メイン画面の原点・AppKit/Quartzの論理的画面境界・backingScaleを確認する。途中の画面変更も停止する。物理ピクセルへの換算は加えない。
5. 全startupサンプルのAX/CG矩形、対象識別子、PID、windowID、phase、時刻、画面情報をdriver.jsonlへ残す。通常observeでも、CGと照合したAX値をそのまま使い、直後の別AX値を採用しない。
6. FixtureはNSView→NSWindow→screenの公開座標変換で空白コンテンツの範囲を記録する。Driverはそこから12ポイント内側の領域だけを候補にする。タイトルバー、ウィンドウボタン、resize境界を開始点に使わない。TabbedのDragMonitorはCommand付きdown/dragを扱うため、今回のsmokeではタイトルバーをドラッグする必要はない。
7. 各入力前に現在のAX/CG一致、前面PID、最前面CG windowID、対象コンテンツとCG領域内の点を検査し、system-wide AX hitが同じPIDの同じAXウィンドウを返すことも要求する。AXが別パネルを返した場合は止める。既存のE2E用CG overlay例外をAX hitの例外に広げないため、E2Eはそこで停止する可能性がある（未実証）。

入力保持中には収束待ちを行わず、違いが出たら既存のrelease経路で停止する。入力lease・watchdogの範囲は変更していない。OSによる確認とイベント送信の競合を完全にはなくせないため、専用ゲスト内の他作業を止める前提は残る。

関連の準備スクリプト不具合も修正した。diskutilのWritableVolume/WritableMediaが両方明示falseの場合だけ媒体を受理し、欠落・未知値・どちらかtrueは拒否する。`/bin/pwd -P`で実パス表記を取得し、大文字小文字の違いで/Volumes検査に失敗する経路を減らす。媒体検査の省略やOS設定変更はしない。

## 検証と未確認事項

純粋テストには実測不一致、永続不一致、安定収束、速すぎるサンプル、緩やかなドリフト、途中不一致によるリセット、異なるPID/ID/title/identifier、無効矩形/時刻、タイトルバー/境界除外を追加した。shellのread-only判定は25組の入力を検査する。これらは入力イベントやAXアクセスを行わない。

2枚のうち1枚だけが不安定な場合は両方の安定履歴をリセットし、順序入れ替わり・1枚欠落は停止するケースも検査する。Swift純粋テストは全64 assertions。初回の型検査は配置移動前のSwift module cacheパスとの重複でコンパイラが停止したため、ログを保全し、ビルド出力ごとの新規cacheへ変更した。古いキャッシュや成果物は削除していない。

型検査・ビルド・純粋テスト・署名・ISO往復の結果とハッシュは別のbuild-resultに記録する。今回の0.3はホストでアプリを起動せず、ゲスト実行・権限変更・Tabbed本体E2Eも行わない。自動アニメーション抑制の効果、AX hitの公開要素、安定判定が実OS上で収束するか、合成Command受信はいずれも未実証。

次の最小実証は、別途承認された0.3のISO/ZIP/bundle/署名を検証し、同じ固定guestパスで必要なHarness許可のみ確認した後、smokeを1回開始すること。after-launch/after-activationの全サンプルと安定結果、入力tag付きdown→drag→up、Command/左button解放、元の2ウィンドウの幾何不変を分けて確認する。もし収束しなければログを保全して停止し、閾値を広げて通さない。Tabbed本体のE2Eは後続の別段階とする。
