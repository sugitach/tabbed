# Guest smoke 実測 2026-10-21

この文書は旧0.1試行直後の履歴。後続0.2の導入・権限事前検査停止と、旧アプリの退避・終了後の状態は[後続記録](guest-smoke-v02-result-20261021.md)を参照。

対象は既に承認された旧0.1 ISO `private/tabbed-guest-harness/exports/20261021T015525Z/Tabbed-Guest-Harness.iso`。ホストで再計算した SHA256 は `afd9af0f8cbf8252c572328e7568b736ba6852af2314ebfc7bbc539a2a50d8eb`。新0.2成果物はゲストで起動していない。

UTMマネージャの `Tabbed-Test` 外部ドライブでこの ISO を選択すると、「ファイルを開けませんでした」と通知された。通知を閉じた後、ゲストには `Tabbed-Guest-Harness` が新たにマウントされていた。マネージャの媒体表示は旧名 `Tabbed-Quit-Fix.iso` のままで、両表示は食い違っている。ゲスト `diskutil info` は Apple_HFS/HFS+、Media Read-Only=Yes、Volume Read-Only=Yes、mount `/Volumes/Tabbed-Guest-Harness` と返した。UTM のエラー原因・マネージャ表示の遅延/誤表示は未確定。

ゲスト SystemVersion.plist は macOS 26.6.2 / build 25G83。Harness起動画面でも VM flag=1 を表示。最初の Terminal で `sw_vers` と sysctl のアンダースコアがキーボード転送によってハイフンになり、それぞれ command not found/unknown oid となったため、SystemVersion.plist とアプリ画面で確認した。これはユーザーの認証情報やOS設定を変えていない。

媒体内 `shasum -a 256 -c SHA256SUMS` は全4件 OK、`HARNESS.ZIP` は外部記録値 `f9f22a1837baa381c80642913133c1eda0ca5aff2305f7883f8d349b2375160d` と一致。新規 `~/Tabbed-Guest-Harness-Test` に ditto 展開、全bundleファイルの BUNDLE.SHA は OK。内包 `Tabbed Guest Fixture.app` と外側 `Tabbed Guest Harness.app` の strict codesign は共に valid on disk / satisfies its Designated Requirement。guest内では再署名も一括属性削除もしていない。

ゲストのプライバシーとセキュリティ→アクセシビリティで、固定展開先の `Tabbed Guest Harness.app` のみ追加して ON を確認した。設定解除の認証はユーザーから直接指定された既存ゲスト資格情報で行い、本記録・ソース・ログには値を残さない。既存の `Tabbed Quit Fix` 項目は変更していない。別の guest 権限要求は観測していない。event-post preflight の独立した成功値は UI に表示されないため未確定。

承認済みの transport smoke を **1回** 手動開始した。run ID は `39C43AA9-3157-4605-8D84-CFAC5C12AE23`。試験用の青/緑2ウィンドウが生成され、Harnessは `STOP/FAIL: AX / WindowServer geometry disagreement` と表示した。guest `~/Library/Application Support/TabbedGuestHarness/<run ID>/result.json` の mode=`TRANSPORT_SMOKE`、result=`STOP_OR_FAIL: AX / WindowServer geometry disagreement`、frames=[]。driver.jsonlは START と同じ失敗を記録。fixture.jsonはPID=1677、ウィンドウID258/259、初期フレーム x=30/470, y=785, w=360, h=270 を記録。`input.json` は存在しない。ソース順序上、これは最初の observe→fixtureElements 中で、`gesture()`/`InputLease`作成より前。今回の合成Command/マウスイベントは送信されておらず、この試行に由来する押下保持はない。実際のAX/WindowServer両フレーム値は旧版ログに残らず、差の原因は未確定。重複試行はしていない。Tabbedは起動せず、E2Eも未実施。

ゲストには失敗結果とログ、実行中のHarness/Fixture、2枚の試験ウィンドウ、未保存のTextEdit書類、読み取り専用媒体が残る。未保存書類を破棄せず、試験用ウィンドウも証跡として残した。ネットワーク・共有フォルダ・クリップボード・clean VMは変更していない。0.2以降では幾何不一致に両測定値を結果へ記録する診断変更をソースへ加えたが、変更版のゲスト実行には別途判断が必要。
