# Accessibility許可後の起動と更新時の署名（2026-10-23）

許可ON後の自動監視開始に加え、自身の署名確認と、古い登録の削除・再登録を案内するダイアログを追加した。非GUI回帰46/46・本体ビルド・署名確認APIの読み取り試験に成功した。実macOSのダイアログ表示・再登録操作は未検証。再登録自体の自動化や継続した証明書署名への変更は含めない。インストール済みアプリ・権限・キーチェーンは変更していない。

## ブランチの依存関係

`fix/accessibility-permission-recovery`はdevelop `d715b6704433b8bcdccade98cee79be41d8d9099`から分岐する。本体は前回の`fix/chrome-tab-transfer-and-quit-recovery`の終了経路を拡張し、テストは`test/chrome-tab-transfer-and-quit-recovery`を拡張するため、双方が統合されたdevelopを基点に一つの変更単位として保存する。既存回帰には一時AXエラーの保持修正も含む。mainや既存の修正枝は変更しない。

## アプリ側の変更

従来は起動時に一度だけ許可を問い合わせ、未許可ならそのまま戻っていた。SDKの`AXIsProcessTrustedWithOptions`の説明ではシステムへの通知は非同期で、直後の戻り値には反映されない。

- 未許可での起動時はアプリ独自の案内を一度表示する。システムへの許可要求は「Open Accessibility Settings…」をユーザーが選んだときに行う。以降は非通知の`AXIsProcessTrusted()`を1秒ごとに確認する。
- 許可取得後にイベント監視の作成・有効化が成功して初めてアイコンとメニューを有効状態にする。失敗時は両監視を停止し、5秒以上の間隔で再試行する。
- 監視とWorkspace通知は一度だけ登録する。成功後・Quit開始時に許可待ちタイマーを破棄し、復元失敗でKeep Openを選んだ後も監視を再開しない。
- メニューに待機・監視開始失敗・稼働・停止を表示し、許可を手動で再確認する項目を追加する。

これは許可後の再起動を通常不要にする実装であり、自動再起動やTCC登録の削除は行わない。OS側が現在のプロセスに許可を反映しない場合の解消は未確認で、すべての再起動要求をなくしたとは判断しない。

## 古い登録が疑われる場合の案内

公開Security APIで自身のコードオブジェクトを取得し、署名の有効性とad-hocフラグを読み取る。Accessibilityの許可判定には別途`AXIsProcessTrusted()`を使う。有効な署名だけで許可済みとは判断しない。

未許可なら、設定でアプリを追加してONにする手順を示す。「すでにONなのに動かない」場合はTabbedの古い項目だけを−で削除し、+で現在のアプリを追加し直すよう案内する。実行中のbundleのパスを表示し、「Show Current App in Finder」でそのアプリを選択表示できる。「Not Now」で閉じても許可待ちは継続し、タイマーから同じダイアログを繰り返し表示しない。メニューの「Accessibility Permission Help…」から再表示できる。

有効なad-hoc署名なら更新後の識別変化の可能性を説明する。署名確認失敗なら原因不明として一般的な手順だけを示す。TCC内部の旧項目を検出したとは表示せず、権限の削除・付与や別アプリの登録変更は行わない。公開API: [SecCodeCopySelf](https://developer.apple.com/documentation/security/seccodecopyself(_:_:)) / [SecCodeCopySigningInformation](https://developer.apple.com/documentation/security/seccodecopysigninginformation(_:_:_:))。

## 更新時に登録が残る問題

現行版と保全した旧版を`codesign -d -r-`で比較した。どちらもad-hoc署名で、指定要件（designated requirement）は次の異なるコードハッシュを要求していた。

| 対象 | 指定要件のcdhash |
| --- | --- |
| 現行dev-20261023-d715b67 | `33c2b4a9064c3847713e1aa2216c4100886bcf5d` |
| 保全した旧dev-20261022-402b19a | `a0fdd139ab2120c205cfe3a927b0cbef12939f8f` |

[Apple DTSの説明](https://developer.apple.com/forums/thread/718331)では、TCCが更新前後のアプリを追跡するには継続した署名identityが必要で、ad-hoc署名は適さない。この仕様と実際の指定要件から、今回の再登録問題の有力な原因と判断する。ただしTCC内部の登録内容は調査・変更しておらず、今回の症状の原因を実機で確定したわけではない。

読み取り専用の`security find-identity -v -p codesigning`では利用可能なコード署名identityは0件だった。次の更新でも同じ署名者とbundle IDを使う方針に変更する必要がある。Apple Development/Developer IDを使う案、個人利用向けに固定した自己署名証明書を使う案がある。[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)は自己署名を説明しているが、各OSサブシステムの受理方針は異なる。自己署名への移行だけでこのMacのAccessibility許可が維持されるとは未検証であり、Developer IDや公証の代わりにもならない。

証明書・秘密鍵の新規作成、キーチェーン登録、信頼設定の変更は別途対象を確認してから行う。移行時には一度、ユーザーによる許可の再登録が必要になる可能性がある。bundle IDだけを要求するような弱い指定要件への変更、TCC直接編集、許可リセットの自動実行はしない。

## 検証と残る確認

`bash Tests/test.sh internal`で46/46が成功。実際の起動判定・controller開始・Quit・案内メソッドを抽出し、AX許可・イベント監視・UI表示を模擬した。未許可→許可、監視作成失敗→回復、二重開始、Quit中の遅延callback、Keep Open後の再開防止に加え、案内の条件付き文言・設定を開く選択・現在のアプリの表示・閉じた後の待機・許可済み/停止済みでの案内抑止を確認した。OSのイベントtap作成やタイマーの実run loop配送、ダイアログ表示の実測ではない。

案内追加前の40件を未修正develop `d715b6704433b8bcdccade98cee79be41d8d9099`のSourcesに適用すると、コンパイルに成功したうえで起動関連7件が失敗し33/40となった。案内追加後も本体全体とXCTestアダプターの宣言shim型検査が成功。フルXCTestは実行していない。

修正後SourcesのスナップショットをCLT/SDK26.5・arm64・macOS14.0対象で最適化ビルドし、リンクまで成功した。配布用app/ZIPの作成、署名変更、起動・インストール・VM試験はしていない。

署名読み取りのみを行う独立CLIを追加でコンパイル・実行し、実際の`AppCodeSignature.current()`が自身の署名を有効・ad-hocと判定することを確認した。同じCLIに対する`codesign -d --verbose=4`と`codesign --verify --strict`の結果も一致した。このCLIはAppKit/Accessibilityを使わず、設定変更・ウィンドウ操作・権限要求を行わない。Tabbedアプリ本体は実行していない。

残る実機確認は、案内表示とFinder/設定への導線、許可OFFで起動→ON→再起動なしで稼働表示と専用ウィンドウの操作が可能になること。証明書移行を選ぶ場合は、同じ証明書で署名した異なる2ビルドへの更新で許可が引き継がれることも確認する。OSの安全設定を操作する試験は今回実施していない。

ローカル証拠（Git除外）：

- 最新の修正後: `Tests/Regression/results/20261023T034156639678Z/`の`result.json`、`additional-validation.json`と各ログ。
- 案内追加前の40件: `Tests/Regression/results/20261023T032452053489Z/`。
- 修正前への新テスト適用: `/Users/t-sugita/work/private/tabbed-permission-validation/20261023T032422302618Z/`。
- 最新ビルド検査用未実行実行体SHA256: `7612373e5ab96c094e95b2760d7e40c3925ceb4b5d4121336f6f8b21efdc63e1`。配布・インストール用成果物ではない。
