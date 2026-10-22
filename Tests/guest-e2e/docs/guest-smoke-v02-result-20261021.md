# 診断版0.2のゲスト実行結果（2026-10-21）

最新状態: 下記の初回権限停止後、追加承認を受けて同版のAccessibilityを再登録した。再開試行は権限検査を通過し、入力前の座標照合で停止した。詳細は末尾の追記を参照。

ユーザーの「テストの実装が完了しているのなら実行してください」に基づき、変更していない診断版の transport smoke をスクリプトから1回開始した。結果は **権限事前検査で停止**。受信試験は未実施であり、PASSではない。

## 成果物と導入

- ISO: `Tests/guest-e2e/exports/20261021T024058Z/Tabbed-Guest-Harness.iso`
- ISO SHA256: `a5e400c7a6c13e595ed2633a2bac420261e3f67c4ac56a12bd1d65cfb3ab5883`（ホスト再計算一致）
- HARNESS.ZIP SHA256: `18b0903364f8aba8099eb27b3d951f8bd7faef466b6db936e236bc1f26c562af`（ゲスト再計算一致）
- ゲスト画面: macOS 26.6.2 / 25G83、arm64、VM flag=1。

旧Harnessの「Close this run's test windows」で旧Fixtureを閉じ、Harnessを通常終了。大文字小文字を無視する `pgrep -ifl` でも残存しないことを確認した。旧インストールは `~/tabbed-guest-harness-test-v01-39c43aa9` へ上書きせず退避した。旧run `39C43AA9-3157-4605-8D84-CFAC5C12AE23` のログは保全した。

UTMのTabbed-Test外部ドライブで新ISOを選択したところ、前回同様「ファイルを開けませんでした」と表示された。ただしゲストの `/Volumes/Tabbed-Guest-Harness` には新ZIPとTEST.SHが存在し、新ZIPのハッシュも一致した。接続操作を重複せず、ゲストで確認した。diskutilのMedia Read-OnlyとVolume Read-Onlyは両方Yes。plistでは `Writable=false`、`WritableMedia=false`、`WritableVolume=false`。媒体のデバイスはdisk6s2、HFS+、外部USB、251904 bytes。

## 準備スクリプトで見つかった不具合

GUIキーボード転送で `/Volumes` が小文字となり、prepareの文字列検査で停止した。`env -i /bin/pwd` により実際の大文字小文字を取得して再指定したところ、次のread-only検査で停止した。

包装済みTEST.SHは存在しない `ReadOnlyVolume` / `ReadOnlyMedia` キーを参照している。今回のdiskutilが返したのは `WritableVolume` / `WritableMedia` であるため、読み取り専用媒体を誤って拒否した。アプリ展開前の停止であり、安全設定や権限による拒否ではない。ソース・媒体・実行バイナリは今回変更していない。このprepare不具合は未修正。

読み取り専用属性を個別に確認したうえで、媒体SHA256SUMSの全5件を検証し、固定パスを新規mkdir（mode700）、dittoで同じHARNESS.ZIPを展開、BUNDLE.SHAをコピーした。続いて未変更の `bash TEST.SH verify` により全bundleファイルと、Fixture/Harness双方のstrict codesignの成功を確認した。再署名・属性除去・検査無効化はしていない。実ディレクトリ名は `~/tabbed-guest-harness-test`（大文字小文字を区別しないFS上で固定パスと一致）。

## 実行とログ

媒体ディレクトリで次を1回実行した。

```sh
bash ./TEST.SH run smoke --confirm-isolated-guest
```

- Run ID: `44EDB7B8-C0F6-4714-AB82-2DD1210ADBDF`
- Mode: `TRANSPORT_SMOKE`
- Result: `STOP_OR_FAIL: Accessibility / event-post permission missing. No request or setting change was made.`
- frames: `[]`
- driver.jsonl: 同じSTOP/FAILのみ、uptime `9833.5787250833346`。
- ログ保存先: `~/Library/Application Support/TabbedGuestHarness/44EDB7B8-C0F6-4714-AB82-2DD1210ADBDF/`
- 同ディレクトリはdriver.jsonl（213 bytes）とresult.json（350 bytes）のみ。fixture.json/input.jsonは未生成。

ログはゲストTerminal上で読み取り確認した内容を本書に転記した。生ログをホストへ転送したとは扱わない。事前検査はAXとevent-postをまとめたguardであり、どちらがfalseかを今回のログから個別には特定できない。旧版の許可設定だけでは新版の事前検査は通らなかった。TCCの個別状態・原因は未確定。

ソース上、権限検査はSTART記録・Fixture起動・InputLease生成より前である。今回の合成Command/マウス入力は未送信で、この試行由来の押下保持はない。受信・座標比較・Tabbedのグループ化・通常Quitは未検証。Tabbed本体は起動していない。権限変更や同じ試験の再実行はしていない。

## 終了時の状態と次の操作

診断版Harnessを通常終了し、画面から消えたことを確認した。ゲストは稼働中。新版と旧版退避、両runのログ、読み取り専用媒体、Terminal、未保存TextEdit文書を保全した。ホスト権限・ネットワーク・共有・clipboard・アカウント・ロック設定・clean VMを変更していない。コード変更、再ビルド、XCTest実行、commit/pushもしていない。

続行には固定パスの診断版Harnessに対するゲスト内アクセシビリティ／イベント送信の許可状態の確認・必要な再登録が必要。追加権限が必要なら停止するという依頼条件に従い、ここで停止した。許可の再設定と同一成果物でのsmoke再実行は次の承認対象。prepareのキー修正は別の未完事項であり、現在の一連の処理を全自動成功とは扱わない。

## 追記: Accessibility再登録後の同版試行

ユーザーがゲストAccessibility再登録と同じ診断版のsmoke再開を承認。ゲスト固定パスのHarness実行ファイルSHA256を再計算し、`93b10029435a2b7f7ae44c041017eb0e469604148c86ee6cb4736644c5917303` と一致した。ホストISOハッシュも上記と一致。バイナリ・媒体・スクリプトは変更していない。

ゲストのシステム設定→プライバシーとセキュリティ→アクセシビリティで、Tabbed Guest Harnessだけを削除し、testホームの固定 `tabbed-guest-harness-test` 内の同アプリを選び直した。追加後ONを確認。既存のTabbed Quit Fix項目は変更していない。今回、新たな認証画面や追加種類の権限要求は発生しなかった。

Terminalのフォーカス切り替え直後の最初の入力は `bash` の先頭文字が欠け、`ash: command not found` で終了した。この入力ではスクリプトもアプリも起動していないことを確認してから、完全なコマンドを入力表示で確認しReturnした。実際に開始したsmokeは再登録後1回だけ。

- Run ID: `4F5E5841-CF6C-450C-AAAC-8D455EF0EAFD`
- Mode: `TRANSPORT_SMOKE`
- Result: `STOP_OR_FAIL: AX / WindowServer geometry disagreement: AX=RectRecord(x: 30.0, y: 785.0, width: 360.0, height: 270.0) CG=RectRecord(x: 34.0, y: 788.0, width: 352.0, height: 264.0)`
- frames: `[]`
- driver.jsonl: START（uptime `10749.068385666667`）、上記STOP/FAIL（`10749.230513333334`）。
- fixture.json: PID2126、windowID289/290、初期フレームA=(30,785,360,270)、B=(470,785,360,270)、各識別子は `TGH-<run ID>-0` / `-1`。
- 保存先: `~/Library/Application Support/TabbedGuestHarness/4F5E5841-CF6C-450C-AAAC-8D455EF0EAFD/`
- 保存ファイル: driver.jsonl 568 bytes、fixture.json 440 bytes、result.json 429 bytes。input.jsonは未生成。

STARTは `preflight` 完了後に記録されるため、今回のAXIsProcessTrustedとCGPreflightPostEventAccessは両方通過した。一方、最初のobserveで停止しており、gesture/InputLease生成前である。合成入力の送信・受信は未実施。この試行に由来するCommand/マウス押下保持はない。Tabbed本体は起動していない。

AX/CGは同じ中心(210,920)を持ち、CGの幅・高さはAXの約97.78%だった。STARTから停止まで約0.162秒であり、生成直後の表示アニメーションなど時間的な差は調査候補だが、今回の単一観測だけで原因とは断定しない。安全な次案は対象PID/識別子/windowIDを維持して複数回の観測で安定を確認する設計の検討。現版の検査閾値を緩める変更や別バイナリ実行は行っていない。

ログ確認後、Harnessの専用ボタンでこのrunのFixture2枚を閉じ、Harnessも通常終了した。ゲストは稼働中で、新版のAX許可はONのまま。全runのログ、新旧アプリ、読み取り専用媒体、Terminal、未保存TextEditを保全。ホスト権限、隔離、別アプリの権限、clean VMは変更していない。生ログはゲストに残し、本書は画面上で確認した値の転記。追加試行・コード変更・build・pushは行っていない。
