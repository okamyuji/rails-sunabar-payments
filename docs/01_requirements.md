# 要件定義書 — rails-sunabar-payments

## 0. V字モデルとトレーサビリティ方針

本プロジェクトはV字モデルに基づき、各工程間のトレーサビリティを確保する。

```
要件定義(本書)  ←――――――――――――→  受入テスト(E2Eテスト)
  ↓                                    ↑
基本設計(02)    ←――――――――――――→  結合テスト
  ↓                                    ↑
詳細設計(03)    ←――――――――――――→  単体テスト
  ↓                                    ↑
           実装(コーディング)
```

### トレーサビリティ規約

- 要件ID: `REQ-XXX-NN`形式(XXX=領域略称、NN=連番)
- 基本設計ID: `BD-XXX-NN`
- 詳細設計ID: `DD-XXX-NN`
- テストID: `UT-XXX-NN`(単体)、`IT-XXX-NN`(結合)、`E2E-XXX-NN`(受入)
- 各設計書・テストケースは対応する上位IDを明記する

## 1. プロジェクト概要

GMOあおぞらネット銀行のsandbox API(sunabar)を利用した決済管理システムを、Ruby3.4/Rails8.1でRailsらしく実装する。Go版(go-sunabar-payments)と同等の機能を持ちつつ、DDDを無理に適用せず、ActiveRecordモデル中心のVanilla Rails設計とする。

### 1.1 目的

- sunabar APIを利用した振込依頼・状態管理・入金消込を一気通貫で行う
- Transactional Outboxパターンで外部API呼び出しの信頼性を確保する
- Rails8.1の標準機能(SolidQueue、Rails.event等)を最大限活用する

### 1.2 技術スタック

| 項目 | 選定 |
|------|------|
| 言語 | Ruby3.4(YJIT有効) |
| フレームワーク | Rails8.1 |
| DB | MySQL8.0 |
| ジョブキュー | SolidQueue |
| コンテナ | Docker(compose.yml) |
| フォーマッタ | syntax_tree(stree) |
| リンタ | RuboCop |
| 型チェック | Sorbet |
| テスト | Minitest + Capybara(E2E) |

## 2. 機能要件(MECEロジックツリー)

機能要件を「ビジネスドメイン」と「運用支援」の2軸に分割する。ビジネスドメインは4領域、運用支援は1領域で、計5領域を網羅する。

```
機能要件
├── ビジネスドメイン(相互排他的な4業務領域)
│   ├── 2.1 口座管理(Account)
│   │   ├── REQ-ACC-01 口座同期
│   │   ├── REQ-ACC-02 口座情報参照
│   │   ├── REQ-ACC-03 バーチャル口座発行
│   │   └── REQ-ACC-04 バーチャル口座一覧
│   ├── 2.2 振込管理(Transfer)
│   │   ├── REQ-TRF-01 振込依頼作成
│   │   ├── REQ-TRF-02 振込状態照会
│   │   ├── REQ-TRF-03 振込一覧取得(※Go版にない新規スコープ)
│   │   ├── REQ-TRF-04 状態遷移管理(状態機械)
│   │   └── REQ-TRF-05 状態チェック再ポーリング(Outbox駆動)
│   ├── 2.3 消込管理(Reconciliation)
│   │   ├── REQ-REC-01 入出金明細取得
│   │   ├── REQ-REC-02 請求書管理(※Go版にない新規スコープ)
│   │   ├── REQ-REC-03 入金消込処理
│   │   └── REQ-REC-04 消込結果通知
│   └── 2.4 通知管理(Notification)
│       ├── REQ-NTF-01 イベント駆動通知
│       └── REQ-NTF-02 通知冪等性
└── 運用支援(ビジネスドメインを横断する管理・監視機能)
    └── 2.5 管理画面(Admin)
        ├── REQ-ADM-01 ダッシュボード
        ├── REQ-ADM-02 振込一覧
        ├── REQ-ADM-03 消込一覧
        └── REQ-ADM-04 Outboxモニタ
```

### 2.1 口座管理(Account)

| ID | 機能 | 説明 |
|----|------|------|
| REQ-ACC-01 | 口座同期 | sunabar APIから口座情報を取得しローカルDBにupsertする。残高は都度API参照、口座メタデータはローカルキャッシュする二層戦略とする |
| REQ-ACC-02 | 口座情報参照 | 同期済み口座情報の参照。残高はsunabar APIからリアルタイム取得する |
| REQ-ACC-03 | バーチャル口座発行 | 入金消込用のバーチャル口座をsunabar API経由で発行する。法人APIトークン(corporateAuth)を使用する |
| REQ-ACC-04 | バーチャル口座一覧 | 発行済みバーチャル口座の一覧を取得する |

### 2.2 振込管理(Transfer)

| ID | 機能 | 説明 |
|----|------|------|
| REQ-TRF-01 | 振込依頼作成 | 振込先口座・金額を指定して振込依頼を作成する。app_request_idで冪等性を担保する。振込日未指定時はJSTの当日日付を設定する |
| REQ-TRF-02 | 振込状態照会 | 個別の振込について現在の状態を返す |
| REQ-TRF-03 | 振込一覧取得 | 振込の一覧をフィルタ・ページネーション付きで取得する(※Go版にない新規スコープ) |
| REQ-TRF-04 | 状態遷移管理 | 下記の状態機械を管理する。楽観的ロック(lock_version)で並行更新を防止する |
| REQ-TRF-05 | 状態チェック再ポーリング | 振込依頼API成功後にTransferStatusCheckScheduledイベントをOutboxに発行し、Relay経由でsunabar結果照会APIを呼び出す。非終端状態(AWAITING_APPROVAL/APPROVED)の場合はstill_in_flightとして再キュー(指数バックオフ)する |

#### 状態遷移図

```
[*] --> PENDING : 振込依頼受付
PENDING --> REQUESTED : sunabar振込依頼API成功
PENDING --> FAILED : sunabar振込依頼API失敗
REQUESTED --> AWAITING_APPROVAL : メールトークン承認待ち検知
REQUESTED --> APPROVED : 承認不要契約
REQUESTED --> SETTLED : 即時着金
REQUESTED --> FAILED : 銀行側拒否
AWAITING_APPROVAL --> APPROVED : 取引パスワード承認完了
AWAITING_APPROVAL --> SETTLED : 承認と着金が同時進行
AWAITING_APPROVAL --> FAILED : 承認タイムアウト
APPROVED --> SETTLED : 着金確認
APPROVED --> FAILED : 着金失敗
SETTLED --> [*]
FAILED --> [*]
```

#### sunabar APIステータスマッピング

| sunabar API応答 | 内部ステータス |
|-----------------|----------------|
| AcceptedToBank | REQUESTED |
| AwaitingApproval | AWAITING_APPROVAL |
| Approved | APPROVED |
| Settled | SETTLED |
| Failed / Rejected | FAILED |

### 2.3 消込管理(Reconciliation)

| ID | 機能 | 説明 |
|----|------|------|
| REQ-REC-01 | 入出金明細取得 | sunabar APIからバーチャル口座の入出金明細を取得し、incoming_transactionsにINSERT IGNORE(UNIQUE制約で重複吸収)する |
| REQ-REC-02 | 請求書管理 | バーチャル口座に紐づく請求書(invoice)のCRUD(※Go版にない新規スコープ。管理画面から操作) |
| REQ-REC-03 | 入金消込処理 | incoming_transactionsとinvoiceを突合し、消込状態を更新する |
| REQ-REC-04 | 消込結果通知 | 消込完了・過入金等の結果をOutboxイベント(ReconciliationCompleted/Excess/Partial)として発行する |

#### 消込状態

| 状態 | 条件 |
|------|------|
| OPEN | 未入金 |
| PARTIAL | 一部入金(入金額<請求額) |
| CLEARED | 完済(入金額=請求額) |
| EXCESS | 過入金(入金額>請求額) |

### 2.4 通知管理(Notification)

| ID | 機能 | 説明 |
|----|------|------|
| REQ-NTF-01 | イベント駆動通知 | 以下のOutboxイベントを受信し通知処理を実行する: TransferAwaitingApproval、TransferSettled、TransferFailed、ReconciliationCompleted、ReconciliationExcess、ReconciliationPartial。初期実装はログ出力(Sender抽象化で将来的にメール/Slack等に差し替え可能とする) |
| REQ-NTF-02 | 通知冪等性 | event_processedテーブルで(event_id, consumer)の一意制約により二重処理を防止する |

### 2.5 管理画面(Admin)

| ID | 機能 | 説明 |
|----|------|------|
| REQ-ADM-01 | ダッシュボード | 振込件数・消込状況・Outboxイベント数のサマリを表示する。集計クエリはActiveRecord asyncで非同期実行する |
| REQ-ADM-02 | 振込一覧 | 振込の状態別フィルタリング、詳細表示、状態遷移履歴の確認 |
| REQ-ADM-03 | 消込一覧 | 請求書と入金の突合状況、消込状態別フィルタリング |
| REQ-ADM-04 | Outboxモニタ | 未処理・処理済みイベントの一覧、リトライ状況の確認 |

## 3. 非機能要件(MECEロジックツリー)

```
非機能要件
├── 3.1 信頼性
│   ├── REQ-REL-01 Transactional Outboxパターン
│   ├── REQ-REL-02 冪等性(二重キー設計)
│   ├── REQ-REL-03 サーキットブレーカー
│   ├── REQ-REL-04 リトライ戦略(5xx/4xx分離)
│   ├── REQ-REL-05 楽観的ロック
│   └── REQ-REL-06 スキップアテンプト
├── 3.2 運用性
│   ├── REQ-OPS-01 Docker compose.yml
│   ├── REQ-OPS-02 YJIT有効化
│   ├── REQ-OPS-03 ヘルスチェック
│   ├── REQ-OPS-04 構造化ログ(相関ID付き)
│   ├── REQ-OPS-05 メトリクスエンドポイント
│   └── REQ-OPS-06 sunabar接続診断(probe)
├── 3.3 品質保証
│   ├── REQ-QA-01 テスト(Minitest 80%+)
│   ├── REQ-QA-02 リンタ(RuboCop)
│   ├── REQ-QA-03 型チェック(Sorbet)
│   ├── REQ-QA-04 フォーマッタ(stree)
│   ├── REQ-QA-05 E2Eテスト(Capybara)
│   └── REQ-QA-06 モックサーバ(mocksunabar)
├── 3.4 セキュリティ
│   ├── REQ-SEC-01 機密情報管理(credentials.yml.enc)
│   └── REQ-SEC-02 APIトークン管理(個人/法人二重トークン)
└── 3.5 CI/CD
    ├── REQ-CI-01 pre-commitフック(gitleaks+品質ゲート)
    └── REQ-CI-02 GitHub Actions(Push時CI)
```

### 3.1 信頼性

#### REQ-REL-01 Transactional Outboxパターン

- ビジネスデータとOutboxイベントを同一トランザクションで書き込む
- SolidQueueのrecurring taskでOutboxテーブルをポーリングし、イベントをディスパッチする
- ポーリング間隔: 5秒(SolidQueueのrecurring task。Go版の2秒に対しRails側の特性を考慮)
- Relayのトランザクション分離レベルはREAD COMMITTEDとする(InnoDB gap lock回避)
- `SELECT ... FOR UPDATE SKIP LOCKED`で複数ワーカー間のデッドロックを防止する

##### Outboxテーブルスキーマ要件

| カラム | 型 | 説明 |
|--------|-----|------|
| id | BIGINT(PK) | 自動採番 |
| aggregate_type | VARCHAR(64) | 集約の種類(Transfer/Reconciliation等) |
| aggregate_id | VARCHAR(64) | 対象レコードのID |
| event_type | VARCHAR(128) | イベント種別 |
| payload | JSON | イベントペイロード |
| status | ENUM(pending/sent/failed) | 処理状態 |
| attempt_count | INT | 試行回数 |
| max_attempts | INT | 最大試行回数(デフォルト10) |
| next_attempt_at | DATETIME(6) | 次回試行日時 |
| last_error | TEXT | 最終エラーメッセージ |
| sent_at | DATETIME(6) | 送信完了日時 |
| created_at | DATETIME(6) | 作成日時 |

##### イベント処理済みテーブルスキーマ要件

| カラム | 型 | 説明 |
|--------|-----|------|
| outbox_event_id | BIGINT(PK) | outbox_events.idへの参照 |
| consumer | VARCHAR(64)(PK) | 消費者識別子 |
| processed_at | DATETIME(6) | 処理日時 |

#### REQ-REL-02 冪等性(二重キー設計)

- app_request_id: クライアントが生成する冪等キー。transfersテーブルにUNIQUE制約。UUID v4を使用
- api_idempotency_key: sunabar API送信用の冪等キー。サーバがUUID v4で生成しUNIQUE制約
- 重複リクエストは既存レコードを返す(INSERT時のUNIQUE違反で検知)
- 内部IDにはUUID v7を使用(時系列順序付き、InnoDBプライマリキーのパフォーマンス向上)

#### REQ-REL-03 サーキットブレーカー

- sunabar API呼び出しの手前にCircuitBreakerを配置
- 状態: CLOSED(通常)→OPEN(遮断)→HALF_OPEN(試行)
- 5xx/接続エラー/タイムアウトのみ失敗カウント対象
- 4xxはCircuitBreakerの失敗数に含めず即FAILED
- OPEN中はsunabar呼び出しをスキップし、Outboxのnext_attempt_atを未来にずらす
- PumaのマルチスレッドでMutexによるスレッドセーフを確保する
- SolidQueueワーカーが別プロセスの場合、プロセスごとに独立したCircuitBreakerインスタンスを持つ(Go版の単一バイナリ共有メモリとは異なる動作)

#### REQ-REL-04 リトライ戦略

| エラー種別 | 対応 |
|------------|------|
| 5xx/接続失敗/timeout | リトライ可。next_attempt_atを指数バックオフ(2^attempt秒、上限10分)で設定 |
| 4xx | リトライ不可。TransferをFAILEDに遷移 |
| 冪等キーTTL切れ疑い | 自動再生成せず停止。運用判断で個別対応 |

#### REQ-REL-05 楽観的ロック

- transfersテーブルにlock_versionカラムを設け、ActiveRecord::Locking::Optimisticを使用する
- RelayワーカーとAPIサーバが同一行を並行更新する際のlost updateを防止する
- StaleObjectErrorをキャッチしてリトライまたは適切なエラー応答を返す

#### REQ-REL-06 スキップアテンプト

- CircuitBreaker OPEN時のOutbox処理では、attempt_countをインクリメントしない
- next_attempt_atのみを5秒後に設定して再キューする
- 正当なイベントが外部サービスの一時障害でFAILEDにされることを防ぐ

### 3.2 運用性

#### REQ-OPS-01 Docker compose.yml

- app(Puma)、worker(SolidQueue)、db(MySQL8.0)の3サービスで構成
- compose.ymlを使用(docker-compose.ymlではない)

#### REQ-OPS-02 YJIT有効化

- Dockerfile内で`ENV RUBY_YJIT_ENABLE=1`を設定

#### REQ-OPS-03 ヘルスチェック

- `/up`エンドポイント(Rails標準)でヘルスチェック

#### REQ-OPS-04 構造化ログ(相関ID付き)

- JSON形式の構造化ログを標準出力に出力
- X-Request-IDヘッダを相関IDとして全ログエントリに付与
- リクエスト→Outbox→sunabar API呼び出しまで相関IDを伝搬する

#### REQ-OPS-05 メトリクスエンドポイント

- `GET /metrics`で以下をJSON返却:
  - outbox_pending_depth(未処理Outboxイベント数)
  - outbox_failed_depth(失敗Outboxイベント数)
  - transfer_status_*(状態別振込件数)

#### REQ-OPS-06 sunabar接続診断(probe)

- `bin/sunabar_probe`スクリプトでsunabar APIへの疎通確認を行う
- Docker環境からの接続テストに使用する

### 3.3 品質保証

#### REQ-QA-01 テスト(Minitest 80%+)

- Model Test + System Testを中核とする(DHH/37signalsのテスト哲学に従う)
- Fixtureと実データベースを使用する
- カバレッジ80%以上を指標(厳密ではなくOK)

#### REQ-QA-02〜04 リンタ/型チェック/フォーマッタ

- RuboCop: コードスタイル統一
- Sorbet: 型チェック(typed: trueから段階的導入)
- stree: コードフォーマット

#### REQ-QA-05 E2Eテスト(Capybara)

- 管理画面の主要操作をCapybaraでテスト

#### REQ-QA-06 モックサーバ(mocksunabar)

- ローカル開発・テスト用にsunabar APIのモックサーバを提供する
- Rackアプリとして実装し、テスト時はWebMockで代替可能とする

### 3.4 セキュリティ

#### REQ-SEC-01 機密情報管理

- sunabar APIトークンはRails credentials(credentials.yml.enc)で管理
- 環境変数でのオーバーライドも可能(SUNABAR_ACCESS_TOKEN等)

#### REQ-SEC-02 APIトークン管理(二重トークン)

- personalAuth: 個人口座API(`/personal/v1/*`)用トークン
- corporateAuth: 法人API(`/corporation/v1/*`)用トークン(バーチャル口座発行等)
- 各トークンを独立して管理・設定可能とする

### 3.5 CI/CD

#### REQ-CI-01 pre-commitフック(gitleaks+品質ゲート)

- gitleaksによる機密情報漏洩チェック
- streeによるフォーマットチェック
- RuboCopによるlintチェック
- Sorbetによる型チェック
- commit前にすべてのゲートを通過させる
- pre-commitフレームワーク(lefthook等)で管理する

#### REQ-CI-02 GitHub Actions(Push時CI)

- Ruby3.4(要件定義と同一バージョン)でCI実行
- MySQL8.0サービスコンテナを使用
- 実行内容:
  - gitleaks(機密情報スキャン)
  - stree(フォーマット検証)
  - RuboCop(lint)
  - Sorbet(型チェック)
  - Minitest(テスト実行+カバレッジ)
- Push時およびPR時に自動実行

## 4. 外部API仕様

### 4.1 sunabar APIレスポンスの特性

- 数値が文字列で返される(例: 残高`"1000000"`、件数`"1"`)。パース処理が必要
- 日付はJST基準。振込日未指定時はJSTの当日を設定する
- 備考(remarks)フィールドが存在する(将来の消込照合に活用可能)

### 4.2 sunabar APIタイムアウト

- 外部API呼び出しのタイムアウト: 5秒

## 5. Go版との機能対応表

| Go版の構成要素 | Rails版での実現方法 |
|----------------|---------------------|
| cmd/api | Pumaによるrails server |
| cmd/relay | SolidQueue recurring task + OutboxRelayJobジョブ |
| cmd/reconciler | SolidQueue recurring task + ReconcileJobジョブ |
| cmd/sunabar-probe | bin/sunabar_probeスクリプト |
| cmd/mocksunabar | test/support/mock_sunabar.rb(Rackアプリ) |
| internal/modules/*/domain/ | app/models/(ActiveRecordモデル) |
| internal/modules/*/application/ | モデルのメソッド + app/models/配下のPORO |
| internal/modules/*/handler/ | app/controllers/(API) + app/jobs/(Outboxハンドラ) |
| internal/modules/*/infrastructure/ | ActiveRecord(組み込み) |
| internal/platform/outbox/ | app/models/outbox_event.rb + app/jobs/outbox_relay_job.rb |
| internal/platform/sunabar/ | app/clients/sunabar_client.rb |
| internal/platform/circuitbreaker/ | app/models/circuit_breaker.rb(PORO、Mutex付き) |
| internal/platform/observability/ | ActiveSupport::Notifications(計装用) + Rails.logger |

### Rails.eventの位置づけ

- Rails.event(ActiveSupport::Notifications)は**計装・観測**目的で使用する
- **モジュール間通信にはOutboxパターンを使用**する(Rails.eventは代替しない)

## 6. 制約事項

- sunabar sandbox APIへの実接続を前提とする
- メールトークン承認はsunabarサービスサイト上で手動操作が必要
- sandbox/本番の6差分(Go記事セクション4)はsandbox前提で設計し、本番対応は将来拡張とする
- DDDの戦術的パターン(Aggregate/Repository/ValueObject)は意図的に採用しない
- 入金の返金・チャージバック・取消はスコープ外とする(paid_amountは増加のみ)
- Outboxイベントのデータ保持ポリシーおよびパージ戦略は本番フェーズで策定する(sandbox期間中は無期限保持)
- Outboxイベントがmax_attemptsを超過してfailedに遷移した場合はログ警告を出力する(運用アラート連携は本番フェーズで策定)
- グレースフルシャットダウンはSolidQueueのデフォルト動作(SIGTERM受信時に処理中イベントを完了してから停止)に準拠する
- 管理画面の認証はBasic認証で保護する(詳細な認可モデルは本番フェーズで策定)
- APIバージョニングはsandboxスコープでは導入しない(本番フェーズで`/api/v1/`プレフィックスを検討)
- Rails標準のタイムゾーン設定は`config.time_zone = "Asia/Tokyo"`とする

## 7. トレーサビリティ対応表(要件定義→受入テスト)

| 要件ID | 要件名 | 対応E2Eテスト | 確認 |
|--------|--------|---------------|------|
| REQ-ACC-01 | 口座同期 | E2E-ACC-01 | ☐ |
| REQ-ACC-02 | 口座情報参照 | E2E-ACC-02 | ☐ |
| REQ-ACC-03 | バーチャル口座発行 | E2E-ACC-03 | ☐ |
| REQ-ACC-04 | バーチャル口座一覧 | E2E-ACC-04 | ☐ |
| REQ-TRF-01 | 振込依頼作成 | E2E-TRF-01 | ☐ |
| REQ-TRF-02 | 振込状態照会 | E2E-TRF-02 | ☐ |
| REQ-TRF-03 | 振込一覧取得 | E2E-TRF-03 | ☐ |
| REQ-TRF-04 | 状態遷移管理 | E2E-TRF-04 | ☐ |
| REQ-TRF-05 | 状態チェック再ポーリング | E2E-TRF-05 | ☐ |
| REQ-REC-01 | 入出金明細取得 | E2E-REC-01 | ☐ |
| REQ-REC-02 | 請求書管理 | E2E-REC-02 | ☐ |
| REQ-REC-03 | 入金消込処理 | E2E-REC-03 | ☐ |
| REQ-REC-04 | 消込結果通知 | E2E-REC-04 | ☐ |
| REQ-NTF-01 | イベント駆動通知 | E2E-NTF-01 | ☐ |
| REQ-NTF-02 | 通知冪等性 | E2E-NTF-02 | ☐ |
| REQ-ADM-01 | ダッシュボード | E2E-ADM-01 | ☐ |
| REQ-ADM-02 | 振込一覧 | E2E-ADM-02 | ☐ |
| REQ-ADM-03 | 消込一覧 | E2E-ADM-03 | ☐ |
| REQ-ADM-04 | Outboxモニタ | E2E-ADM-04 | ☐ |
| REQ-REL-01 | Transactional Outbox | E2E-REL-01 | ☐ |
| REQ-REL-02 | 冪等性 | E2E-REL-02 | ☐ |
| REQ-REL-03 | サーキットブレーカー | E2E-REL-03 | ☐ |
| REQ-REL-04 | リトライ戦略 | E2E-REL-04 | ☐ |
| REQ-REL-05 | 楽観的ロック | E2E-REL-05 | ☐ |
| REQ-REL-06 | スキップアテンプト | E2E-REL-06 | ☐ |
| REQ-OPS-01 | Docker compose.yml | E2E-OPS-01 | ☐ |
| REQ-OPS-02 | YJIT有効化 | E2E-OPS-02 | ☐ |
| REQ-OPS-03 | ヘルスチェック | E2E-OPS-03 | ☐ |
| REQ-OPS-04 | 構造化ログ | E2E-OPS-04 | ☐ |
| REQ-OPS-05 | メトリクスエンドポイント | E2E-OPS-05 | ☐ |
| REQ-OPS-06 | sunabar接続診断 | E2E-OPS-06 | ☐ |
| REQ-QA-01 | テスト80%+ | (CI/CD確認) | ☐ |
| REQ-QA-02 | RuboCop | (CI/CD確認) | ☐ |
| REQ-QA-03 | Sorbet | (CI/CD確認) | ☐ |
| REQ-QA-04 | stree | (CI/CD確認) | ☐ |
| REQ-QA-05 | E2Eテスト | (テスト実行確認) | ☐ |
| REQ-QA-06 | モックサーバ | E2E-QA-06 | ☐ |
| REQ-SEC-01 | 機密情報管理 | E2E-SEC-01 | ☐ |
| REQ-SEC-02 | APIトークン管理 | E2E-SEC-02 | ☐ |
| REQ-CI-01 | pre-commitフック | (CI/CD確認) | ☐ |
| REQ-CI-02 | GitHub Actions | (CI/CD確認) | ☐ |
