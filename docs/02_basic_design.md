# 基本設計書 — rails-sunabar-payments

## 0. 本書の位置づけ

要件定義書(01_requirements.md)に基づき、システム全体のアーキテクチャ、データモデル、モジュール構成、外部連携方式を定義する。

## 1. アーキテクチャ概要

### 1.1 全体構成(MECEロジックツリー)

```
システム構成
├── 1.1.1 アプリケーション層
│   ├── Webサーバ(Puma)
│   │   ├── API(JSON)
│   │   └── 管理画面(HTML)
│   └── バックグラウンドワーカー(SolidQueue)
│       ├── OutboxRelayJob(5秒間隔recurring、ハンドラを同期呼び出し)
│       └── ReconcileJob(10分間隔recurring)
├── 1.1.2 データ層
│   └── MySQL8.0
├── 1.1.3 外部連携
│   └── sunabar API(GMOあおぞらネット銀行sandbox)
└── 1.1.4 インフラ層
    └── Docker(compose.yml)
```

### 1.2 プロセス構成

| サービス | 役割 | Dockerサービス名 |
|----------|------|------------------|
| Puma | HTTP API + 管理画面 | app |
| SolidQueue | Outbox Relay + Reconciler | worker |
| MySQL8.0 | データストア | db |

### 1.3 Outbox Relay ディスパッチモデル(重要設計判断)

OutboxRelayJobはGo版と同様に**ハンドラロジックを同期的にインライン呼び出し**する。個別のSolidQueueジョブにはenqueueしない。

理由: Relayがイベントを`SELECT FOR UPDATE SKIP LOCKED`で取得し、ハンドラを実行し、結果に基づいてステータスを更新するまでを**同一トランザクション内**で完結させる必要がある。別ジョブにenqueueすると、enqueue後にジョブが失敗した場合にイベントが消失する。

```
OutboxRelayJob(recurring, 5秒間隔)
  ├── BEGIN(READ COMMITTED)
  ├── SELECT ... FOR UPDATE SKIP LOCKED
  ├── 各イベントに対して:
  │   ├── event_type → ハンドラクラスを解決
  │   ├── handler.call(event) ← 同期呼び出し
  │   └── 結果に基づきevent.statusを更新
  └── COMMIT
```

ハンドラクラス:
- `Handlers::SendToSunabar` — 振込依頼をsunabarへ送信
- `Handlers::CheckTransferStatus` — sunabarへ振込状態照会
- `Handlers::ProcessNotification` — 通知処理

### 1.4 リクエストフロー

```
[クライアント] → [Puma(API)] → [ActiveRecordモデル] → [MySQL]
                                      ↓ (同一トランザクション)
                               [OutboxEvent作成]
                                      ↓ (SolidQueue recurring 5秒)
                        [OutboxRelayJob] → [ハンドラ同期呼び出し]
                                                ↓
                                        [SunabarClient] → [sunabar API]
```

### 1.5 still_in_flightの扱い(重要設計判断)

`CheckTransferStatus`ハンドラがsunabar APIから非終端状態(AWAITING_APPROVAL/APPROVED)を受け取った場合:
- **attempt_countをインクリメントする**(Go版と同一。正常なリトライとして計上)
- next_attempt_atを指数バックオフで設定して再キュー
- max_attemptsに達した場合はfailedに遷移(運用アラート)

これはCircuitBreaker OPEN時のskip_attempt(attempt_count据え置き)とは**明確に異なる**。skip_attemptはAPI呼び出し自体が行われていない場合に限定する。

## 2. ディレクトリ構成

```
app/
├── clients/
│   └── sunabar_client.rb          # sunabar API HTTPクライアント(Faraday)
├── controllers/
│   ├── api/
│   │   ├── base_controller.rb     # API共通(JSON応答、相関ID、ページネーション)
│   │   ├── accounts_controller.rb
│   │   ├── transfers_controller.rb
│   │   ├── reconciliations_controller.rb
│   │   └── metrics_controller.rb  # メトリクスエンドポイント
│   └── admin/
│       ├── base_controller.rb     # 管理画面共通
│       ├── dashboard_controller.rb
│       ├── transfers_controller.rb
│       ├── invoices_controller.rb
│       ├── reconciliations_controller.rb # 消込状況表示
│       └── outbox_events_controller.rb
├── handlers/
│   ├── send_to_sunabar.rb         # Outboxハンドラ: 振込依頼送信
│   ├── check_transfer_status.rb   # Outboxハンドラ: 状態照会
│   └── process_notification.rb    # Outboxハンドラ: 通知処理
├── jobs/
│   ├── outbox_relay_job.rb        # Outboxポーリング→ハンドラ同期呼び出し
│   └── reconcile_job.rb           # 入金消込バッチ
├── models/
│   ├── concerns/
│   │   ├── outboxable.rb          # Outboxイベント発行Concern
│   │   └── has_status_machine.rb  # 状態遷移管理Concern(宣言的遷移表)
│   ├── account.rb
│   ├── virtual_account.rb
│   ├── transfer.rb
│   ├── outbox_event.rb
│   ├── event_processed.rb
│   ├── incoming_transaction.rb
│   ├── invoice.rb
│   ├── circuit_breaker.rb         # PORO(Mutex、スレッドセーフ)
│   ├── sunabar_status_mapper.rb   # PORO(sunabar→内部ステータス変換)
│   └── notification_sender.rb     # PORO(通知送信抽象。初期実装はログ出力)
└── views/
    └── admin/                     # 管理画面テンプレート(ERB)
config/
├── routes.rb
├── solid_queue.yml
├── database.yml
└── initializers/
    ├── sunabar.rb                 # SunabarClient初期化
    └── circuit_breaker.rb         # CircuitBreakerインスタンス初期化
bin/
└── sunabar_probe                  # sunabar接続診断スクリプト
test/
├── models/
├── controllers/
├── handlers/
├── integration/
├── system/                        # Capybara E2Eテスト
└── support/
    └── mock_sunabar.rb            # sunabar APIモック(WebMock)
```

## 3. データモデル設計(MECEロジックツリー)

```
データモデル
├── 3.1 口座系
│   ├── accounts(口座マスタ)
│   └── virtual_accounts(バーチャル口座)
├── 3.2 振込系
│   └── transfers(振込)
├── 3.3 消込系
│   ├── invoices(請求書)
│   └── incoming_transactions(入金明細)
├── 3.4 イベント基盤系
│   ├── outbox_events(Outboxイベント)
│   └── event_processed(イベント処理済み)
└── 3.5 SolidQueue系(フレームワーク管理)
```

### 3.1 accountsテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BINARY(16) | PK | UUID v7 |
| sunabar_account_id | VARCHAR(64) | UNIQUE, NOT NULL | sunabar側口座ID |
| account_number | VARCHAR(20) | NOT NULL | 口座番号 |
| branch_code | VARCHAR(10) | NOT NULL | 支店コード |
| account_name | VARCHAR(128) | | 口座名義 |
| synced_at | DATETIME(6) | | 最終同期日時 |
| created_at | DATETIME(6) | NOT NULL | |
| updated_at | DATETIME(6) | NOT NULL | |

### 3.2 virtual_accountsテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BINARY(16) | PK | UUID v7 |
| account_id | BINARY(16) | FK(accounts), NOT NULL, INDEX | 親口座 |
| sunabar_va_id | VARCHAR(64) | UNIQUE, NOT NULL | sunabar側VA ID |
| va_number | VARCHAR(20) | NOT NULL | VA口座番号 |
| va_name | VARCHAR(128) | | VA名義 |
| created_at | DATETIME(6) | NOT NULL | |
| updated_at | DATETIME(6) | NOT NULL | |

### 3.3 transfersテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BINARY(16) | PK | UUID v7 |
| account_id | BINARY(16) | FK(accounts), NOT NULL, INDEX | 振込元口座 |
| app_request_id | VARCHAR(64) | UNIQUE, NOT NULL | クライアント冪等キー(UUID v4) |
| api_idempotency_key | CHAR(36) | UNIQUE, NOT NULL | sunabar API冪等キー(UUID v4) |
| status | VARCHAR(20) | NOT NULL, DEFAULT 'pending', INDEX | 状態 |
| destination_bank_code | VARCHAR(10) | NOT NULL | 振込先銀行コード |
| destination_branch_code | VARCHAR(10) | NOT NULL | 振込先支店コード |
| destination_account_number | VARCHAR(20) | NOT NULL | 振込先口座番号 |
| destination_account_type | VARCHAR(10) | NOT NULL, DEFAULT 'ordinary' | 振込先口座種別(ordinary/checking) |
| destination_account_name | VARCHAR(128) | NOT NULL | 振込先口座名義 |
| amount | BIGINT | NOT NULL | 振込金額(円) |
| transfer_date | DATE | NOT NULL | 振込日(JST) |
| remarks | VARCHAR(128) | | 備考 |
| sunabar_apply_no | VARCHAR(64) | | sunabar受付番号 |
| last_error | TEXT | | 最終エラー |
| lock_version | INT | NOT NULL, DEFAULT 0 | 楽観的ロック |
| created_at | DATETIME(6) | NOT NULL | |
| updated_at | DATETIME(6) | NOT NULL | |

**インデックス**: status, account_id, (status, created_at)複合

### 3.4 invoicesテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BINARY(16) | PK | UUID v7 |
| virtual_account_id | BINARY(16) | FK(virtual_accounts), NOT NULL, INDEX | 対象VA |
| amount | BIGINT | NOT NULL | 請求金額(円) |
| paid_amount | BIGINT | NOT NULL, DEFAULT 0 | 入金済み金額 |
| status | VARCHAR(20) | NOT NULL, DEFAULT 'open', INDEX | 状態(open/partial/cleared/excess) |
| description | VARCHAR(256) | | 摘要 |
| due_date | DATE | | 支払期限 |
| lock_version | INT | NOT NULL, DEFAULT 0 | 楽観的ロック |
| created_at | DATETIME(6) | NOT NULL | |
| updated_at | DATETIME(6) | NOT NULL | |

### 3.5 incoming_transactionsテーブル

※INSERT後の更新なし(read-only after insert)。updated_atは意図的に省略する。

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BINARY(16) | PK | UUID v7 |
| virtual_account_id | BINARY(16) | FK(virtual_accounts), NOT NULL, INDEX | 入金先VA |
| sunabar_transaction_id | VARCHAR(64) | UNIQUE, NOT NULL | sunabar側取引ID(INSERT IGNORE用) |
| amount | BIGINT | NOT NULL | 入金額 |
| sender_name | VARCHAR(128) | | 振込人名義 |
| transaction_date | DATE | NOT NULL | 取引日 |
| created_at | DATETIME(6) | NOT NULL | |

### 3.6 outbox_eventsテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | |
| aggregate_type | VARCHAR(64) | NOT NULL, INDEX | 集約種別 |
| aggregate_id | VARCHAR(64) | NOT NULL | 対象ID |
| event_type | VARCHAR(128) | NOT NULL, INDEX | イベント種別 |
| payload | JSON | NOT NULL | ペイロード |
| status | VARCHAR(20) | NOT NULL, DEFAULT 'pending' | pending/sent/failed |
| attempt_count | INT | NOT NULL, DEFAULT 0 | 試行回数 |
| max_attempts | INT | NOT NULL, DEFAULT 10 | 最大試行回数 |
| next_attempt_at | DATETIME(6) | NOT NULL | 次回試行日時 |
| last_error | TEXT | | 最終エラー |
| sent_at | DATETIME(6) | | 送信完了日時 |
| created_at | DATETIME(6) | NOT NULL | |

**複合インデックス**: (status, next_attempt_at)でRelay検索を高速化

### 3.7 event_processedテーブル

| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| outbox_event_id | BIGINT | PK(複合), NOT NULL | outbox_events.idに対応 |
| consumer | VARCHAR(64) | PK(複合), NOT NULL | 消費者識別子 |
| processed_at | DATETIME(6) | NOT NULL | 処理日時 |

## 4. APIエンドポイント設計

### 4.1 エンドポイント一覧(MECEロジックツリー)

```
APIエンドポイント
├── 4.1.1 口座系
│   ├── POST   /api/accounts/sync
│   ├── GET    /api/accounts
│   ├── GET    /api/accounts/:id
│   ├── POST   /api/virtual_accounts
│   └── GET    /api/virtual_accounts
├── 4.1.2 振込系
│   ├── POST   /api/transfers
│   ├── GET    /api/transfers
│   └── GET    /api/transfers/:id
├── 4.1.3 消込系(RPCスタイル: 意図的選択)
│   └── POST   /api/reconciliations/run
├── 4.1.4 運用系
│   ├── GET    /up (ヘルスチェック)
│   └── GET    /api/metrics
└── 4.1.5 管理画面
    ├── GET    /admin (ダッシュボード)
    ├── GET    /admin/transfers
    ├── GET    /admin/transfers/:id
    ├── GET    /admin/invoices
    ├── GET    /admin/invoices/new
    ├── POST   /admin/invoices
    ├── GET    /admin/invoices/:id/edit
    ├── PATCH  /admin/invoices/:id
    ├── DELETE /admin/invoices/:id
    ├── GET    /admin/reconciliations
    └── GET    /admin/outbox_events
```

### 4.2 APIページネーション仕様

全一覧APIはoffsetベースページネーション(pagy)を採用する。

| パラメータ | デフォルト | 最大 |
|------------|-----------|------|
| page | 1 | - |
| per_page | 25 | 100 |

レスポンスエンベロープ:
```json
{
  "data": [...],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total_count": 150,
    "total_pages": 6
  }
}
```

### 4.3 APIフィルタ仕様

#### GET /api/transfers

| パラメータ | 説明 |
|------------|------|
| status | 状態フィルタ(pending/requested/awaiting_approval/approved/settled/failed) |
| from_date | 振込日開始(YYYY-MM-DD) |
| to_date | 振込日終了(YYYY-MM-DD) |

### 4.4 APIリクエスト/レスポンス仕様

#### POST /api/transfers

リクエスト:
```json
{
  "app_request_id": "uuid-v4",
  "account_id": "uuid-v7(振込元口座)",
  "destination_bank_code": "0310",
  "destination_branch_code": "101",
  "destination_account_number": "1234567",
  "destination_account_type": "ordinary",
  "destination_account_name": "テスト タロウ",
  "amount": 10000,
  "transfer_date": "2026-06-20",
  "remarks": "テスト振込"
}
```

レスポンス(201 Created / 200 OK冪等):
```json
{
  "id": "uuid-v7",
  "app_request_id": "uuid-v4",
  "status": "pending",
  "amount": 10000,
  "transfer_date": "2026-06-20",
  "created_at": "2026-06-20T10:00:00.000+09:00"
}
```

#### エラーレスポンス共通形式

```json
{
  "error": {
    "code": "エラーコード",
    "message": "人間が読めるメッセージ",
    "details": [...]
  }
}
```

#### エラーコード一覧

| コード | HTTPステータス | 説明 |
|--------|---------------|------|
| validation_error | 422 | バリデーションエラー |
| not_found | 404 | リソースが見つからない |
| conflict | 409 | 冪等キー重複(既存レコードを200で返す場合もあり) |
| stale_object | 409 | 楽観的ロック競合 |
| circuit_open | 503 | サーキットブレーカーOPEN |
| internal_error | 500 | 内部エラー |

#### StaleObjectError時の動作

- 自動リトライは行わない
- 409 Conflictをクライアントに返し、クライアント側で再取得・再送を促す

## 5. Outboxイベントフロー設計

### 5.1 イベント種別一覧

| イベント種別 | 発行元 | ハンドラ | 説明 |
|-------------|--------|----------|------|
| TransferRequested | Transfer作成時 | SendToSunabar | sunabarへ振込依頼送信 |
| TransferStatusCheckScheduled | sunabar振込依頼成功時 | CheckTransferStatus | sunabarへ状態照会 |
| TransferAwaitingApproval | 承認待ち検知時 | ProcessNotification | 承認待ち通知 |
| TransferSettled | 着金確認時 | ProcessNotification | 着金完了通知 |
| TransferFailed | 失敗時 | ProcessNotification | 失敗通知 |
| ReconciliationCompleted | 消込完了時 | ProcessNotification | 消込完了通知 |
| ReconciliationExcess | 過入金検知時 | ProcessNotification | 過入金アラート通知 |
| ReconciliationPartial | 一部入金時 | ProcessNotification | 一部入金通知 |

### 5.2 Outbox Relayの処理フロー

```
OutboxRelayJob(5秒間隔recurring、排他実行)
  ↓
SET TRANSACTION ISOLATION LEVEL READ COMMITTED
BEGIN
  ↓
SELECT * FROM outbox_events
  WHERE status = 'pending'
  AND next_attempt_at <= NOW()
  ORDER BY created_at
  LIMIT 10
  FOR UPDATE SKIP LOCKED
  ↓
各イベントに対してハンドラを同期呼び出し:
  ├── 成功 → status='sent', sent_at=NOW()
  ├── still_in_flight → attempt_count++, next_attempt_at=指数バックオフ
  ├── skip_attempt(CB OPEN) → next_attempt_atを5秒後(attempt_count据え置き)
  ├── retryable_error(5xx等) → attempt_count++, next_attempt_at=指数バックオフ
  └── non_retryable_error(4xx等) → status='failed', last_error記録
  ↓
COMMIT
```

**排他実行**: SolidQueueのrecurring taskは`exclusive`オプションで、前回実行が完了するまで次回をスキップする。

### 5.3 振込の全体シーケンス

```
[Client] → POST /api/transfers
  → Transfer.create!(status: pending) + OutboxEvent(TransferRequested)
  → 201 Created

[OutboxRelayJob] → TransferRequested取得
  → Handlers::SendToSunabar.call(event)
    → CircuitBreaker.allow?
      ├── OPEN → skip_attempt(5秒後再キュー、attempt_count据え置き)
      └── CLOSED/HALF_OPEN
          → SunabarClient.request_transfer(timeout: 5秒)
            ├── 成功 → Transfer.status=requested
            │         + OutboxEvent(TransferStatusCheckScheduled)
            ├── 5xx/timeout → retryable_error(attempt_count++、指数バックオフ)
            └── 4xx → Transfer.status=failed + OutboxEvent(TransferFailed)

[OutboxRelayJob] → TransferStatusCheckScheduled取得
  → Handlers::CheckTransferStatus.call(event)
    → SunabarClient.get_transfer_status
      → SunabarStatusMapper.map(response_status)
        ├── AWAITING_APPROVAL → Transfer.status更新 + OutboxEvent(TransferAwaitingApproval)
        │                       still_in_flight(attempt_count++、バックオフ再キュー)
        ├── APPROVED → Transfer.status更新、still_in_flight(再キュー)
        ├── SETTLED → Transfer.status=settled + OutboxEvent(TransferSettled)
        └── FAILED → Transfer.status=failed + OutboxEvent(TransferFailed)
```

## 6. サーキットブレーカー設計

### 6.1 パラメータ

| パラメータ | 値 | 説明 |
|------------|-----|------|
| failure_threshold | 3 | OPEN遷移までの連続失敗数(Go版と同一) |
| failure_rate_threshold | 50% | rolling window内の失敗率閾値 |
| rolling_window | 30秒 | 失敗率計算対象期間 |
| min_requests | 5 | 失敗率評価の最小リクエスト数(低トラフィック時の誤OPEN防止) |
| reset_timeout | 30秒 | OPEN→HALF_OPEN遷移までの待機時間 |
| half_open_max_probes | 2 | HALF_OPEN中の並列試行許容数 |
| gateway_timeout | 5秒 | sunabar API呼び出しタイムアウト |

### 6.2 実装方針

- app/models/circuit_breaker.rbにPOROとして実装
- Monitor(Mutex)でスレッドセーフを確保
- プロセスごとに独立インスタンス(SolidQueueワーカーとPumaは別プロセス)
- 状態はインメモリ管理(プロセス再起動でCLOSEDにリセット)
- failure_thresholdとfailure_rate_thresholdはOR条件(いずれかに達した時点でOPENに遷移)

## 7. SunabarClient設計

### 7.1 HTTPクライアント

- Faradayを使用(Rails8.1エコシステムで標準的)
- タイムアウト: 接続5秒、読み取り5秒
- レスポンスパース: sunabar APIの数値文字列(`"1000000"`)をIntegerに変換する`parse_int`ヘルパ
- 日時パース: sunabar固有の日時フォーマットを`Time`に変換する`parse_time`ヘルパ

### 7.2 認証

- personalAuth: `Authorization: Bearer <token>`ヘッダ(個人口座API)
- corporateAuth: `Authorization: Bearer <token>`ヘッダ(法人API)
- トークンは`Rails.application.credentials`または環境変数から取得

### 7.3 エラークラス階層

```ruby
module SunabarErrors
  class Error < StandardError; end
  class ClientError < Error; end      # 4xx
  class ServerError < Error; end      # 5xx
  class TimeoutError < Error; end     # タイムアウト
  class ConnectionError < Error; end  # 接続失敗
end
```

### 7.4 リトライ方針

- SunabarClient自体はリトライしない(Outbox Relayが管理)
- エラー種別を返し、Relayが5xx/4xxを判断する

## 8. ルーティング設計

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    post "accounts/sync", to: "accounts#sync"
    resources :accounts, only: [:index, :show]
    resources :virtual_accounts, only: [:index, :create]
    resources :transfers, only: [:index, :show, :create]
    post "reconciliations/run", to: "reconciliations#run"
    get "metrics", to: "metrics#show"
  end

  namespace :admin do
    get "/", to: "dashboard#show"
    resources :transfers, only: [:index, :show]
    resources :invoices
    resources :reconciliations, only: [:index]
    resources :outbox_events, only: [:index, :show]
  end
end
```

## 9. SolidQueue設計

### 9.1 solid_queue.yml

```yaml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: ["outbox", "default"]
      threads: 3
      processes: 1
      polling_interval: 0.1
  recurring:
    reconcile:
      class: ReconcileJob
      schedule: "*/10 * * * *"
```

**OutboxRelayJobのポーリング方式**: SolidQueueの標準cronは分単位のため、5秒間隔ポーリングはジョブ自己再投入方式で実現する。OutboxRelayJobは処理完了後に`OutboxRelayJob.set(wait: 5.seconds).perform_later`で自身を再投入する。初回起動はinitializerで行う。`limits_concurrency key: "outbox_relay", to: 1`で排他実行を保証する。

### 9.2 キュー構成

| キュー | 用途 | 優先度 |
|--------|------|--------|
| outbox | OutboxRelayJob(recurring) | 高(先頭指定) |
| default | ReconcileJob、その他 | 通常 |

### 9.3 排他実行

- OutboxRelayJobは前回のインスタンスが実行中なら次回をスキップする
- SolidQueueのrecurring taskの`concurrency_limit: 1`で制御

## 10. 管理画面設計

### 10.1 画面一覧

| 画面 | パス | 説明 |
|------|------|------|
| ダッシュボード | /admin | 振込件数・消込状況・Outbox深度。`load_async`で非同期集計 |
| 振込一覧 | /admin/transfers | 状態別フィルタ、pagy |
| 振込詳細 | /admin/transfers/:id | 状態遷移履歴、関連Outboxイベント |
| 請求書一覧 | /admin/invoices | 消込状態別フィルタ、pagy |
| 請求書作成/編集 | /admin/invoices/new,edit | フォーム |
| 消込状況 | /admin/reconciliations | VA別の入金と請求書の突合状況 |
| Outboxモニタ | /admin/outbox_events | 状態別フィルタ、リトライ状況 |

### 10.2 管理画面方針

- Rails標準のERBテンプレート(SPAにしない)
- CSSはTailwind CSS(Rails8.1標準)
- ページネーションはpagy gem
- ダッシュボード集計はActiveRecord `load_async`で非同期実行

## 11. ログ設計

### 11.1 構造化ログ

- lograge gemでJSON形式の構造化ログを出力
- 各ログエントリにrequest_id(X-Request-ID)を付与
- OutboxRelayJob内でもrequest_idを生成し、ハンドラからsunabar API呼び出しまで伝搬

### 11.2 DB接続プール

| プロセス | スレッド数 | プールサイズ |
|----------|-----------|-------------|
| Puma | 5(デフォルト) | 5 |
| SolidQueue worker | 3 | 5 |

database.ymlのpoolはスレッド数以上に設定する。

## 12. CI/CD設計

### 12.1 pre-commitフック(lefthook)

```yaml
# lefthook.yml
pre-commit:
  parallel: true
  commands:
    gitleaks:
      run: gitleaks detect --source . --no-banner --no-color
      fail_text: "機密情報が検出されました"
    stree:
      glob: "*.rb"
      run: bundle exec stree check {staged_files}
    rubocop:
      glob: "*.rb"
      run: bundle exec rubocop --force-exclusion {staged_files}
    sorbet:
      run: bundle exec srb tc
```

### 12.2 GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: password
          MYSQL_DATABASE: rails_sunabar_test
        ports: ["3306:3306"]
        options: >-
          --health-cmd="mysqladmin ping"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=3
    env:
      RAILS_ENV: test
      DATABASE_URL: mysql2://root:password@127.0.0.1:3306/rails_sunabar_test
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: true
      - name: gitleaks
        uses: gitleaks/gitleaks-action@v2
      - run: bundle exec stree check app lib
      - run: bundle exec rubocop
      - run: bundle exec srb tc
      - run: bundle exec rails db:setup
      - run: bundle exec rails test
        env:
          COVERAGE: true
      - run: bundle exec rails test:system
      - name: Check coverage
        run: |
          ruby -e "require 'json'; c = JSON.parse(File.read('coverage/.last_run.json')); exit 1 if c['result']['line'] < 80"
```

## 13. HasStatusMachine Concern設計

### 13.1 宣言的遷移表

Go版の`validTransitions`マップと同等の宣言的遷移テーブルをConcernで実装する。

```ruby
# app/models/concerns/has_status_machine.rb の設計意図
# Transfer.valid_transitions のような形式で遷移ルールを定義
# 遷移前のバリデーションでActiveRecord::RecordInvalidを発生させる
```

遷移表:
```
pending → [requested, failed]
requested → [awaiting_approval, approved, settled, failed]
awaiting_approval → [approved, settled, failed]
approved → [settled, failed]
settled → (終端)
failed → (終端)
```

## 14. トレーサビリティ対応表(要件定義→基本設計)

| 要件ID | 要件名 | 基本設計ID | 基本設計要素 | 確認 |
|--------|--------|-----------|-------------|------|
| REQ-ACC-01 | 口座同期 | BD-ACC-01 | POST /api/accounts/sync, Account.sync! | ☐ |
| REQ-ACC-02 | 口座情報参照 | BD-ACC-02 | GET /api/accounts/:id, SunabarClient | ☐ |
| REQ-ACC-03 | VA発行 | BD-ACC-03 | POST /api/virtual_accounts, corporateAuth | ☐ |
| REQ-ACC-04 | VA一覧 | BD-ACC-04 | GET /api/virtual_accounts | ☐ |
| REQ-TRF-01 | 振込依頼 | BD-TRF-01 | POST /api/transfers, Outboxable | ☐ |
| REQ-TRF-02 | 振込状態照会 | BD-TRF-02 | GET /api/transfers/:id | ☐ |
| REQ-TRF-03 | 振込一覧 | BD-TRF-03 | GET /api/transfers(新規) | ☐ |
| REQ-TRF-04 | 状態遷移 | BD-TRF-04 | HasStatusMachine, lock_version | ☐ |
| REQ-TRF-05 | 再ポーリング | BD-TRF-05 | CheckTransferStatus, still_in_flight | ☐ |
| REQ-REC-01 | 明細取得 | BD-REC-01 | ReconcileJob, INSERT IGNORE | ☐ |
| REQ-REC-02 | 請求書管理 | BD-REC-02 | /admin/invoices CRUD(新規) | ☐ |
| REQ-REC-03 | 消込処理 | BD-REC-03 | ReconcileJob, Invoice#apply_payment | ☐ |
| REQ-REC-04 | 消込通知 | BD-REC-04 | Outbox(ReconciliationCompleted等) | ☐ |
| REQ-NTF-01 | 通知 | BD-NTF-01 | ProcessNotification, NotificationSender | ☐ |
| REQ-NTF-02 | 通知冪等性 | BD-NTF-02 | EventProcessed, INSERT IGNORE | ☐ |
| REQ-ADM-01 | ダッシュボード | BD-ADM-01 | /admin, load_async集計 | ☐ |
| REQ-ADM-02 | 振込一覧UI | BD-ADM-02 | /admin/transfers, フィルタ/pagy | ☐ |
| REQ-ADM-03 | 消込一覧UI | BD-ADM-03 | /admin/reconciliations, 状態フィルタ | ☐ |
| REQ-ADM-04 | Outboxモニタ | BD-ADM-04 | /admin/outbox_events | ☐ |
| REQ-REL-01 | Outbox | BD-REL-01 | outbox_events, OutboxRelayJob(同期) | ☐ |
| REQ-REL-02 | 冪等性 | BD-REL-02 | UNIQUE(app_request_id, api_idempotency_key) | ☐ |
| REQ-REL-03 | CB | BD-REL-03 | CircuitBreaker PORO, Monitor | ☐ |
| REQ-REL-04 | リトライ | BD-REL-04 | 指数バックオフ(2^n秒, 上限10分)、5xx/4xx分離 | ☐ |
| REQ-REL-05 | 楽観ロック | BD-REL-05 | lock_version, 409 Conflict | ☐ |
| REQ-REL-06 | スキップ | BD-REL-06 | skip_attempt, attempt_count据え置き | ☐ |
| REQ-OPS-01 | Docker | BD-OPS-01 | compose.yml(app/worker/db) | ☐ |
| REQ-OPS-02 | YJIT | BD-OPS-02 | ENV RUBY_YJIT_ENABLE=1 | ☐ |
| REQ-OPS-03 | ヘルスチェック | BD-OPS-03 | GET /up | ☐ |
| REQ-OPS-04 | 構造化ログ | BD-OPS-04 | lograge JSON, request_id伝搬 | ☐ |
| REQ-OPS-05 | メトリクス | BD-OPS-05 | GET /api/metrics | ☐ |
| REQ-OPS-06 | probe | BD-OPS-06 | bin/sunabar_probe | ☐ |
| REQ-QA-01 | テスト80%+ | BD-QA-01 | Minitest + SimpleCov, CI coverage check | ☐ |
| REQ-QA-02 | RuboCop | BD-QA-02 | lefthook + CI | ☐ |
| REQ-QA-03 | Sorbet | BD-QA-03 | lefthook + CI | ☐ |
| REQ-QA-04 | stree | BD-QA-04 | lefthook + CI | ☐ |
| REQ-QA-05 | E2Eテスト | BD-QA-05 | test/system/ Capybara | ☐ |
| REQ-QA-06 | モック | BD-QA-06 | test/support/mock_sunabar.rb(WebMock) | ☐ |
| REQ-SEC-01 | 機密管理 | BD-SEC-01 | credentials.yml.enc + ENV | ☐ |
| REQ-SEC-02 | 二重トークン | BD-SEC-02 | personalAuth/corporateAuth設定分離 | ☐ |
| REQ-CI-01 | pre-commit | BD-CI-01 | lefthook(parallel: gitleaks/stree/rubocop/sorbet) | ☐ |
| REQ-CI-02 | GitHub Actions | BD-CI-02 | .github/workflows/ci.yml + coverage check | ☐ |
