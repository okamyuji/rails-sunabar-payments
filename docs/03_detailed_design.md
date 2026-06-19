# 詳細設計書 — rails-sunabar-payments

## 0. 本書の位置づけ

基本設計書(02_basic_design.md)に基づき、実装に直結するクラス設計、メソッド仕様、DB migration、テストケースを定義する。

## 1. マイグレーション設計(MECEロジックツリー)

```
マイグレーション
├── 1.1 001_create_accounts
├── 1.2 002_create_virtual_accounts
├── 1.3 003_create_transfers
├── 1.4 004_create_invoices
├── 1.5 005_create_incoming_transactions
├── 1.6 006_create_outbox_events
├── 1.7 007_create_event_processed
└── 1.8 008_create_reconciliation_matches
```

### 1.1 001_create_accounts

```ruby
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.string :sunabar_account_id, limit: 64, null: false
      t.string :account_number, limit: 20, null: false
      t.string :branch_code, limit: 10, null: false
      t.string :account_name, limit: 128
      t.datetime :synced_at, precision: 6
      t.timestamps precision: 6
    end

    execute "ALTER TABLE accounts ADD PRIMARY KEY (id)"
    add_index :accounts, :sunabar_account_id, unique: true
  end
end
```

### 1.2 002_create_virtual_accounts

```ruby
class CreateVirtualAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :virtual_accounts, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.binary :account_id, limit: 16, null: false
      t.string :sunabar_va_id, limit: 64, null: false
      t.string :va_number, limit: 20, null: false
      t.string :va_name, limit: 128
      t.timestamps precision: 6
    end

    execute "ALTER TABLE virtual_accounts ADD PRIMARY KEY (id)"
    add_index :virtual_accounts, :sunabar_va_id, unique: true
    add_index :virtual_accounts, :account_id
    add_foreign_key :virtual_accounts, :accounts, column: :account_id
  end
end
```

### 1.3 003_create_transfers

```ruby
class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.binary :account_id, limit: 16, null: false
      t.string :app_request_id, limit: 64, null: false
      t.string :api_idempotency_key, limit: 36, null: false
      t.string :status, limit: 20, null: false, default: "pending"
      t.string :destination_bank_code, limit: 10, null: false
      t.string :destination_branch_code, limit: 10, null: false
      t.string :destination_account_number, limit: 20, null: false
      t.string :destination_account_type, limit: 10, null: false, default: "ordinary"
      t.string :destination_account_name, limit: 128, null: false
      t.bigint :amount, null: false
      t.date :transfer_date, null: false
      t.string :remarks, limit: 128
      t.string :sunabar_apply_no, limit: 64
      t.text :last_error
      t.integer :lock_version, null: false, default: 0
      t.timestamps precision: 6
    end

    execute "ALTER TABLE transfers ADD PRIMARY KEY (id)"
    add_index :transfers, :app_request_id, unique: true
    add_index :transfers, :api_idempotency_key, unique: true
    add_index :transfers, :status
    add_index :transfers, :account_id
    add_index :transfers, [:status, :created_at]
    add_foreign_key :transfers, :accounts, column: :account_id
  end
end
```

### 1.4 004_create_invoices

```ruby
class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.binary :virtual_account_id, limit: 16, null: false
      t.bigint :amount, null: false
      t.bigint :paid_amount, null: false, default: 0
      t.string :status, limit: 20, null: false, default: "open"
      t.string :description, limit: 256
      t.date :due_date
      t.integer :lock_version, null: false, default: 0
      t.timestamps precision: 6
    end

    execute "ALTER TABLE invoices ADD PRIMARY KEY (id)"
    add_index :invoices, :virtual_account_id
    add_index :invoices, :status
    add_foreign_key :invoices, :virtual_accounts, column: :virtual_account_id
  end
end
```

### 1.5 005_create_incoming_transactions

```ruby
class CreateIncomingTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :incoming_transactions, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.binary :virtual_account_id, limit: 16, null: false
      t.string :sunabar_transaction_id, limit: 64, null: false
      t.bigint :amount, null: false
      t.string :sender_name, limit: 128
      t.date :transaction_date, null: false
      t.datetime :created_at, precision: 6, null: false
    end

    execute "ALTER TABLE incoming_transactions ADD PRIMARY KEY (id)"
    add_index :incoming_transactions, :sunabar_transaction_id, unique: true
    add_index :incoming_transactions, :virtual_account_id
    add_foreign_key :incoming_transactions, :virtual_accounts, column: :virtual_account_id
  end
end
```

### 1.6 006_create_outbox_events

```ruby
class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events do |t|
      t.string :aggregate_type, limit: 64, null: false
      t.string :aggregate_id, limit: 64, null: false
      t.string :event_type, limit: 128, null: false
      t.json :payload, null: false
      t.string :status, limit: 20, null: false, default: "pending"
      t.integer :attempt_count, null: false, default: 0
      t.integer :max_attempts, null: false, default: 10
      t.datetime :next_attempt_at, precision: 6, null: false
      t.text :last_error
      t.datetime :sent_at, precision: 6
      t.timestamps precision: 6
    end

    add_index :outbox_events, [:status, :next_attempt_at]
    add_index :outbox_events, :aggregate_type
    add_index :outbox_events, :event_type
  end
end
```

### 1.7 007_create_event_processed

```ruby
class CreateEventProcessed < ActiveRecord::Migration[8.1]
  def change
    create_table :event_processed, id: false do |t|
      t.bigint :outbox_event_id, null: false
      t.string :consumer, limit: 64, null: false
      t.datetime :processed_at, precision: 6, null: false
    end

    execute "ALTER TABLE event_processed ADD PRIMARY KEY (outbox_event_id, consumer)"
    add_foreign_key :event_processed, :outbox_events, column: :outbox_event_id
  end
end
```

### 1.8 008_create_reconciliation_matches

入金明細と請求書の突合を追跡し、二重カウントを防止するジョインテーブル。

```ruby
class CreateReconciliationMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_matches, id: false do |t|
      t.binary :incoming_transaction_id, limit: 16, null: false
      t.binary :invoice_id, limit: 16, null: false
      t.bigint :applied_amount, null: false
      t.datetime :created_at, precision: 6, null: false
    end

    execute "ALTER TABLE reconciliation_matches ADD PRIMARY KEY (incoming_transaction_id, invoice_id)"
    add_foreign_key :reconciliation_matches, :incoming_transactions, column: :incoming_transaction_id
    add_foreign_key :reconciliation_matches, :invoices, column: :invoice_id
    add_index :reconciliation_matches, :invoice_id
  end
end
```

## 2. UUID戦略

全モデルでBINARY(16)のUUID v7をPKに使用する。JSONシリアライゼーションとActiveRecordの相互運用のため、ApplicationRecordにUUID型属性を定義する。

### 2.1 ApplicationRecord

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.uuid_primary_key
    attribute :id, :uuid_binary
    before_create :assign_uuid_v7

    define_method(:assign_uuid_v7) do
      self.id ||= SecureRandom.uuid_v7
    end
  end

  def id_for_payload
    UuidBinaryType.to_uuid_string(id_before_type_cast)
  end
end
```

### 2.2 UuidBinaryType

```ruby
# app/types/uuid_binary_type.rb
class UuidBinaryType < ActiveRecord::Type::Binary
  def cast(value)
    return nil if value.nil?
    return value if value.is_a?(String) && value.bytesize == 16

    hex = value.to_s.delete("-")
    [hex].pack("H*")
  end

  def deserialize(value)
    return nil if value.nil?

    self.class.to_uuid_string(value)
  end

  def serialize(value)
    cast(value)
  end

  def self.to_uuid_string(binary)
    return nil if binary.nil?

    hex = binary.unpack1("H*")
    "#{hex[0..7]}-#{hex[8..11]}-#{hex[12..15]}-#{hex[16..19]}-#{hex[20..31]}"
  end
end

# config/initializers/types.rb
ActiveRecord::Type.register(:uuid_binary, UuidBinaryType)
```

これにより、`render json: transfer`でidがUUID文字列として出力される。Outboxペイロードでもid_for_payloadで文字列化する。

## 3. モデル設計(MECEロジックツリー)

```
モデル
├── 3.1 ActiveRecordモデル
│   ├── Account
│   ├── VirtualAccount
│   ├── Transfer
│   ├── Invoice
│   ├── IncomingTransaction
│   ├── OutboxEvent
│   ├── EventProcessed
│   └── ReconciliationMatch
├── 3.2 Concern
│   ├── Outboxable
│   └── HasStatusMachine
└── 3.3 PORO
    ├── CircuitBreaker
    ├── SunabarStatusMapper
    ├── NotificationSender
    └── SunabarErrors
```

### 3.1 Account

```ruby
# app/models/account.rb
class Account < ApplicationRecord
  uuid_primary_key

  has_many :virtual_accounts, dependent: :destroy
  has_many :transfers, dependent: :restrict_with_error

  validates :sunabar_account_id, presence: true, uniqueness: true
  validates :account_number, presence: true
  validates :branch_code, presence: true

  def self.sync!(client: SunabarClient.instance)
    response = client.list_accounts
    response[:accounts].each do |acc|
      record = find_or_initialize_by(sunabar_account_id: acc[:accountId])
      record.assign_attributes(
        account_number: acc[:accountNumber],
        branch_code: acc[:branchCode],
        account_name: acc[:accountName],
        synced_at: Time.current
      )
      record.save!
    end
  end

  def fetch_balance(client: SunabarClient.instance)
    client.get_balance(account_id: sunabar_account_id)
  end
end
```

### 3.2 VirtualAccount

```ruby
# app/models/virtual_account.rb
class VirtualAccount < ApplicationRecord
  uuid_primary_key

  belongs_to :account
  has_many :invoices, dependent: :restrict_with_error
  has_many :incoming_transactions, dependent: :restrict_with_error

  validates :sunabar_va_id, presence: true, uniqueness: true
  validates :va_number, presence: true

  def self.issue!(account:, va_name:, client: SunabarClient.instance)
    response = client.issue_virtual_account(
      account_id: account.sunabar_account_id,
      va_name: va_name
    )
    create!(
      account: account,
      sunabar_va_id: response[:vaId],
      va_number: response[:vaNumber],
      va_name: va_name
    )
  end
end
```

### 3.3 Transfer

```ruby
# app/models/transfer.rb
class Transfer < ApplicationRecord
  uuid_primary_key
  include HasStatusMachine
  include Outboxable

  belongs_to :account

  STATUSES = %w[pending requested awaiting_approval approved settled failed].freeze
  TERMINAL_STATUSES = %w[settled failed].freeze

  define_transitions(
    pending: %i[requested failed],
    requested: %i[awaiting_approval approved settled failed],
    awaiting_approval: %i[approved settled failed],
    approved: %i[settled failed]
  )

  validates :app_request_id, presence: true, uniqueness: true
  validates :api_idempotency_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :destination_bank_code, presence: true
  validates :destination_branch_code, presence: true
  validates :destination_account_number, presence: true
  validates :destination_account_name, presence: true
  validates :transfer_date, presence: true

  before_validation :set_defaults, on: :create

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_date_range, ->(from, to) {
    relation = all
    relation = relation.where(transfer_date: from..) if from
    relation = relation.where(transfer_date: ..to) if to
    relation
  }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def self.create_with_outbox!(params)
    transaction do
      transfer = create!(params)
      transfer.publish_outbox_event!(
        event_type: "TransferRequested",
        payload: { transfer_id: transfer.id_for_payload }
      )
      transfer
    end
  end

  # 冪等性: insert-first方式。UNIQUE違反時に既存レコードを返す(TOCTOU排除)
  def self.find_or_create_idempotent!(params)
    create_with_outbox!(params)
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?("app_request_id")
    find_by!(app_request_id: params[:app_request_id])
  end

  private

  def set_defaults
    self.api_idempotency_key ||= SecureRandom.uuid
    self.transfer_date ||= Time.current.in_time_zone("Asia/Tokyo").to_date
  end
end
```

### 3.4 Invoice

```ruby
# app/models/invoice.rb
class Invoice < ApplicationRecord
  uuid_primary_key
  include Outboxable

  belongs_to :virtual_account
  has_many :reconciliation_matches, dependent: :destroy

  STATUSES = %w[open partial cleared excess].freeze

  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :pending_reconciliation, -> { where(status: %w[open partial]) }

  # 消込状態は金額から決定的に導出されるため、HasStatusMachineは使わない
  def apply_payment(payment_amount)
    new_paid = paid_amount + payment_amount
    new_status = determine_status(new_paid)
    update!(paid_amount: new_paid, status: new_status)

    event_type = case new_status
                 when "cleared" then "ReconciliationCompleted"
                 when "excess" then "ReconciliationExcess"
                 when "partial" then "ReconciliationPartial"
                 end

    publish_outbox_event!(
      event_type: event_type,
      payload: { invoice_id: id_for_payload }
    ) if event_type
  end

  private

  def determine_status(paid)
    if paid.zero?
      "open"
    elsif paid < amount
      "partial"
    elsif paid == amount
      "cleared"
    else
      "excess"
    end
  end
end
```

### 3.5 IncomingTransaction

```ruby
# app/models/incoming_transaction.rb
class IncomingTransaction < ApplicationRecord
  uuid_primary_key
  self.record_timestamps = false

  belongs_to :virtual_account
  has_many :reconciliation_matches, dependent: :destroy

  validates :sunabar_transaction_id, presence: true, uniqueness: true
  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_date, presence: true

  def self.upsert_from_sunabar!(va:, transactions:)
    transactions.each do |txn|
      insert(
        {
          id: UuidBinaryType.new.cast(SecureRandom.uuid_v7),
          virtual_account_id: va.id_before_type_cast,
          sunabar_transaction_id: txn[:transaction_id],
          amount: txn[:amount],
          sender_name: txn[:sender_name],
          transaction_date: txn[:transaction_date],
          created_at: Time.current
        },
        unique_by: :sunabar_transaction_id
      )
    end
  end

  def matched?
    reconciliation_matches.exists?
  end
end
```

### 3.6 ReconciliationMatch

```ruby
# app/models/reconciliation_match.rb
class ReconciliationMatch < ApplicationRecord
  self.primary_key = [:incoming_transaction_id, :invoice_id]
  self.record_timestamps = false

  belongs_to :incoming_transaction
  belongs_to :invoice

  validates :applied_amount, numericality: { greater_than: 0 }
end
```

### 3.7 OutboxEvent

```ruby
# app/models/outbox_event.rb
class OutboxEvent < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze
  BACKOFF_CAP = 600

  validates :aggregate_type, presence: true
  validates :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_dispatchable, -> {
    where(status: "pending")
      .where("next_attempt_at <= ?", Time.current)
      .order(:created_at)
      .limit(10)
      .lock("FOR UPDATE SKIP LOCKED")
  }

  def mark_sent!
    update!(status: "sent", sent_at: Time.current)
  end

  def mark_failed!(error_message)
    update!(status: "failed", last_error: error_message)
  end

  # attempt_countインクリメント+次回試行日時を単一updateで原子的に更新
  def record_retryable_error!(error_message)
    new_count = attempt_count + 1
    if new_count >= max_attempts
      update!(status: "failed", attempt_count: new_count, last_error: error_message)
    else
      update!(
        attempt_count: new_count,
        next_attempt_at: Time.current + backoff_seconds(new_count),
        last_error: error_message
      )
    end
  end

  # still_in_flight: API成功だが非終端状態。attempt_countインクリメントあり
  def record_still_in_flight!
    new_count = attempt_count + 1
    if new_count >= max_attempts
      update!(
        status: "failed",
        attempt_count: new_count,
        last_error: "max attempts reached while still in flight"
      )
    else
      update!(
        attempt_count: new_count,
        next_attempt_at: Time.current + backoff_seconds(new_count)
      )
    end
  end

  # skip_attempt: CB OPEN。attempt_countインクリメントなし
  def record_skip_attempt!
    update!(next_attempt_at: Time.current + 5)
  end

  private

  def backoff_seconds(count)
    [2**count, BACKOFF_CAP].min
  end
end
```

### 3.8 EventProcessed

```ruby
# app/models/event_processed.rb
class EventProcessed < ApplicationRecord
  self.table_name = "event_processed"
  self.primary_key = [:outbox_event_id, :consumer]

  def self.already_processed?(outbox_event_id:, consumer:)
    exists?(outbox_event_id: outbox_event_id, consumer: consumer)
  end

  def self.mark_processed!(outbox_event_id:, consumer:)
    insert(
      { outbox_event_id: outbox_event_id, consumer: consumer, processed_at: Time.current },
      unique_by: [:outbox_event_id, :consumer]
    )
  end
end
```

### 3.9 Outboxable Concern

```ruby
# app/models/concerns/outboxable.rb
module Outboxable
  extend ActiveSupport::Concern

  def publish_outbox_event!(event_type:, payload: {})
    OutboxEvent.create!(
      aggregate_type: self.class.name,
      aggregate_id: respond_to?(:id_for_payload) ? id_for_payload : id.to_s,
      event_type: event_type,
      payload: payload,
      next_attempt_at: Time.current
    )
  end
end
```

### 3.10 HasStatusMachine Concern

```ruby
# app/models/concerns/has_status_machine.rb
module HasStatusMachine
  extend ActiveSupport::Concern

  class InvalidTransition < StandardError; end

  class_methods do
    def define_transitions(map)
      @status_transitions = map.transform_keys(&:to_s)
                               .transform_values { |v| v.map(&:to_s) }
    end

    def status_transitions
      @status_transitions || {}
    end
  end

  def transition_to!(new_status)
    allowed = self.class.status_transitions[status]
    unless allowed&.include?(new_status.to_s)
      raise InvalidTransition,
        "#{self.class.name}: #{status}から#{new_status}への遷移は許可されていません"
    end
    update!(status: new_status)
  end
end
```

### 3.11 CircuitBreaker

```ruby
# app/models/circuit_breaker.rb
class CircuitBreaker
  class OpenError < StandardError; end

  CLOSED = :closed
  OPEN = :open
  HALF_OPEN = :half_open

  def initialize(
    failure_threshold: 3,
    failure_rate_threshold: 0.5,
    rolling_window: 30,
    min_requests: 5,
    reset_timeout: 30,
    half_open_max_probes: 2
  )
    @failure_threshold = failure_threshold
    @failure_rate_threshold = failure_rate_threshold
    @rolling_window = rolling_window
    @min_requests = min_requests
    @reset_timeout = reset_timeout
    @half_open_max_probes = half_open_max_probes
    @state = CLOSED
    @failures = []
    @successes = []
    @consecutive_failures = 0
    @last_failure_at = nil
    @half_open_probes = 0
    @monitor = Monitor.new
  end

  def allow?(now = Time.current)
    @monitor.synchronize do
      case @state
      when CLOSED
        true
      when OPEN
        if now - @last_failure_at >= @reset_timeout
          @state = HALF_OPEN
          @half_open_probes = 0
          true
        else
          false
        end
      when HALF_OPEN
        if @half_open_probes < @half_open_max_probes
          @half_open_probes += 1
          true
        else
          false
        end
      end
    end
  end

  def record_success(now = Time.current)
    @monitor.synchronize do
      @successes << now
      @consecutive_failures = 0
      @state = CLOSED if @state == HALF_OPEN
      prune_window(now)
    end
  end

  def record_failure(now = Time.current)
    @monitor.synchronize do
      @failures << now
      @consecutive_failures += 1
      @last_failure_at = now
      prune_window(now)

      if @state == HALF_OPEN
        @state = OPEN
      elsif should_open?
        @state = OPEN
      end
    end
  end

  def state
    @monitor.synchronize { @state }
  end

  private

  def should_open?
    return true if @consecutive_failures >= @failure_threshold

    total = @failures.size + @successes.size
    return false if total < @min_requests

    failure_rate = @failures.size.to_f / total
    failure_rate >= @failure_rate_threshold
  end

  def prune_window(now)
    cutoff = now - @rolling_window
    @failures.reject! { |t| t < cutoff }
    @successes.reject! { |t| t < cutoff }
  end
end
```

### 3.12 SunabarStatusMapper

```ruby
# app/models/sunabar_status_mapper.rb
class SunabarStatusMapper
  MAPPING = {
    "AcceptedToBank" => "requested",
    "AwaitingApproval" => "awaiting_approval",
    "Approved" => "approved",
    "Settled" => "settled",
    "Failed" => "failed",
    "Rejected" => "failed"
  }.freeze

  def self.map(sunabar_status)
    MAPPING.fetch(sunabar_status) do
      raise ArgumentError, "不明なsunabarステータス: #{sunabar_status}"
    end
  end

  def self.terminal?(internal_status)
    %w[settled failed].include?(internal_status)
  end
end
```

### 3.13 NotificationSender

```ruby
# app/models/notification_sender.rb
class NotificationSender
  def send_notification(event_type:, payload:)
    Rails.logger.info(
      { event: "notification_sent", event_type: event_type, payload: payload }.to_json
    )
  end
end
```

### 3.14 SunabarErrors

```ruby
# app/models/sunabar_errors.rb
module SunabarErrors
  class Error < StandardError; end
  class ClientError < Error; end
  class ServerError < Error; end
  class TimeoutError < Error; end
  class ConnectionError < Error; end
end
```

## 4. ハンドラ設計(MECEロジックツリー)

```
ハンドラ(Outboxイベント処理、OutboxRelayJobから同期呼び出し)
├── 4.1 Handlers::SendToSunabar
├── 4.2 Handlers::CheckTransferStatus
└── 4.3 Handlers::ProcessNotification
```

### 4.1 Handlers::SendToSunabar

```ruby
# app/handlers/send_to_sunabar.rb
module Handlers
  class SendToSunabar
    class SkipAttemptError < StandardError; end

    def initialize(circuit_breaker:, client: SunabarClient.instance)
      @circuit_breaker = circuit_breaker
      @client = client
    end

    def call(event)
      transfer = Transfer.find_by!(id: event.payload["transfer_id"])
      return :success if transfer.terminal?

      unless @circuit_breaker.allow?
        raise SkipAttemptError, "CircuitBreaker OPEN"
      end

      response = @client.request_transfer(
        idempotency_key: transfer.api_idempotency_key,
        account_id: transfer.account.sunabar_account_id,
        destination_bank_code: transfer.destination_bank_code,
        destination_branch_code: transfer.destination_branch_code,
        destination_account_number: transfer.destination_account_number,
        destination_account_type: transfer.destination_account_type,
        destination_account_name: transfer.destination_account_name,
        amount: transfer.amount,
        transfer_date: transfer.transfer_date,
        remarks: transfer.remarks
      )

      @circuit_breaker.record_success
      transfer.transaction do
        transfer.update!(sunabar_apply_no: response[:apply_no])
        transfer.transition_to!("requested")
        transfer.publish_outbox_event!(
          event_type: "TransferStatusCheckScheduled",
          payload: { transfer_id: transfer.id_for_payload }
        )
      end
      :success
    rescue SunabarErrors::ClientError => e
      transfer.transaction do
        transfer.update!(last_error: e.message)
        transfer.transition_to!("failed")
        transfer.publish_outbox_event!(
          event_type: "TransferFailed",
          payload: { transfer_id: transfer.id_for_payload, error: e.message }
        )
      end
      :non_retryable
    rescue SunabarErrors::ServerError, SunabarErrors::TimeoutError, SunabarErrors::ConnectionError => e
      @circuit_breaker.record_failure
      transfer.update!(last_error: e.message)
      [:retryable, e.message]
    rescue SkipAttemptError
      :skip_attempt
    end
  end
end
```

### 4.2 Handlers::CheckTransferStatus

```ruby
# app/handlers/check_transfer_status.rb
module Handlers
  class CheckTransferStatus
    class SkipAttemptError < StandardError; end

    def initialize(circuit_breaker:, client: SunabarClient.instance)
      @circuit_breaker = circuit_breaker
      @client = client
    end

    def call(event)
      transfer = Transfer.find_by!(id: event.payload["transfer_id"])
      return :success if transfer.terminal?

      unless @circuit_breaker.allow?
        raise SkipAttemptError, "CircuitBreaker OPEN"
      end

      response = @client.get_transfer_status(apply_no: transfer.sunabar_apply_no)
      @circuit_breaker.record_success

      internal_status = SunabarStatusMapper.map(response[:status])

      if SunabarStatusMapper.terminal?(internal_status)
        transfer.transaction do
          transfer.transition_to!(internal_status)
          event_type = internal_status == "settled" ? "TransferSettled" : "TransferFailed"
          transfer.publish_outbox_event!(
            event_type: event_type,
            payload: { transfer_id: transfer.id_for_payload }
          )
        end
        :success
      else
        if transfer.status != internal_status
          transfer.transaction do
            transfer.transition_to!(internal_status)
            if internal_status == "awaiting_approval"
              transfer.publish_outbox_event!(
                event_type: "TransferAwaitingApproval",
                payload: { transfer_id: transfer.id_for_payload }
              )
            end
          end
        end
        :still_in_flight
      end
    rescue SunabarErrors::ServerError, SunabarErrors::TimeoutError, SunabarErrors::ConnectionError => e
      @circuit_breaker.record_failure
      transfer&.update!(last_error: e.message)
      [:retryable, e.message]
    rescue SunabarErrors::ClientError => e
      transfer.transaction do
        transfer.update!(last_error: e.message)
        transfer.transition_to!("failed")
        transfer.publish_outbox_event!(
          event_type: "TransferFailed",
          payload: { transfer_id: transfer.id_for_payload, error: e.message }
        )
      end
      :non_retryable
    rescue SkipAttemptError
      :skip_attempt
    end
  end
end
```

### 4.3 Handlers::ProcessNotification

```ruby
# app/handlers/process_notification.rb
module Handlers
  class ProcessNotification
    def initialize(sender: NotificationSender.new)
      @sender = sender
    end

    def call(event)
      return :success if EventProcessed.already_processed?(
        outbox_event_id: event.id, consumer: "notification"
      )

      @sender.send_notification(
        event_type: event.event_type,
        payload: event.payload
      )

      EventProcessed.mark_processed!(
        outbox_event_id: event.id, consumer: "notification"
      )
      :success
    end
  end
end
```

## 5. ジョブ設計

### 5.1 OutboxRelayJob

**重要**: イベントごとに独立したトランザクションで処理する。外部API呼び出しを含むため、バッチ全体を1トランザクションにまとめると長時間ロック保持になる。

```ruby
# app/jobs/outbox_relay_job.rb
class OutboxRelayJob < ApplicationJob
  queue_as :outbox
  limits_concurrency key: "outbox_relay", to: 1

  HANDLER_MAP = {
    "TransferRequested" => ->(cb) { Handlers::SendToSunabar.new(circuit_breaker: cb) },
    "TransferStatusCheckScheduled" => ->(cb) { Handlers::CheckTransferStatus.new(circuit_breaker: cb) },
    "TransferAwaitingApproval" => ->(_) { Handlers::ProcessNotification.new },
    "TransferSettled" => ->(_) { Handlers::ProcessNotification.new },
    "TransferFailed" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationCompleted" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationExcess" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationPartial" => ->(_) { Handlers::ProcessNotification.new }
  }.freeze

  def perform
    event_ids = fetch_pending_event_ids
    event_ids.each { |eid| process_event(eid) }
  ensure
    self.class.set(wait: 5.seconds).perform_later
  end

  private

  def fetch_pending_event_ids
    OutboxEvent.transaction(isolation: :read_committed) do
      OutboxEvent.pending_dispatchable.pluck(:id)
    end
  end

  def process_event(event_id)
    OutboxEvent.transaction(isolation: :read_committed) do
      event = OutboxEvent.where(id: event_id).lock("FOR UPDATE SKIP LOCKED").first
      return unless event && event.status == "pending"

      dispatch(event)
    end
  end

  def dispatch(event)
    handler_factory = HANDLER_MAP[event.event_type]
    unless handler_factory
      event.mark_failed!("不明なイベント種別: #{event.event_type}")
      return
    end

    handler = handler_factory.call(circuit_breaker)
    result = handler.call(event)

    # ハンドラは:symbolまたは[:symbol, "error message"]を返す
    status, error_msg = Array(result)

    case status
    when :success then event.mark_sent!
    when :still_in_flight then event.record_still_in_flight!
    when :skip_attempt then event.record_skip_attempt!
    when :retryable then event.record_retryable_error!(error_msg || "retryable error")
    when :non_retryable then event.mark_failed!(error_msg || "non-retryable error")
    end
  rescue => e
    event.record_retryable_error!(e.message)
  end

  def circuit_breaker
    @circuit_breaker ||= Rails.application.config.circuit_breaker
  end
end
```

### 5.2 ReconcileJob

```ruby
# app/jobs/reconcile_job.rb
class ReconcileJob < ApplicationJob
  queue_as :default

  def perform
    VirtualAccount.find_each do |va|
      reconcile_va(va)
    end
  end

  private

  def reconcile_va(va)
    client = SunabarClient.instance
    transactions = client.list_transactions(va_id: va.sunabar_va_id)
    IncomingTransaction.upsert_from_sunabar!(va: va, transactions: transactions)

    unmatched = IncomingTransaction
      .where(virtual_account_id: va.id)
      .left_joins(:reconciliation_matches)
      .where(reconciliation_matches: { incoming_transaction_id: nil })

    unmatched.find_each do |txn|
      invoice = va.invoices.pending_reconciliation.order(:due_date, :created_at).first
      next unless invoice

      Invoice.transaction do
        ReconciliationMatch.create!(
          incoming_transaction: txn,
          invoice: invoice,
          applied_amount: txn.amount,
          created_at: Time.current
        )
        invoice.apply_payment(txn.amount)
      end
    end
  rescue SunabarErrors::Error, ActiveRecord::ActiveRecordError => e
    Rails.logger.error(
      { event: "reconcile_failed", va_id: va.id, error: e.message }.to_json
    )
  end
end
```

## 6. コントローラ設計(MECEロジックツリー)

```
コントローラ
├── 6.1 API
│   ├── Api::BaseController
│   ├── Api::AccountsController
│   ├── Api::TransfersController
│   ├── Api::ReconciliationsController
│   └── Api::MetricsController
└── 6.2 Admin
    ├── Admin::BaseController(ActionController::Base継承、CSRF有効)
    ├── Admin::DashboardController
    ├── Admin::TransfersController
    ├── Admin::InvoicesController
    ├── Admin::ReconciliationsController
    └── Admin::OutboxEventsController
```

### 6.1 Api::BaseController

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ActionController::API
    include Pagy::Backend

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
    rescue_from ActiveRecord::StaleObjectError, with: :stale_object
    rescue_from ActiveRecord::InvalidForeignKey, with: :invalid_reference
    rescue_from HasStatusMachine::InvalidTransition, with: :conflict

    before_action :set_request_id

    private

    def not_found(_e)
      render json: { error: { code: "not_found", message: "リソースが見つかりません" } }, status: :not_found
    end

    def unprocessable(e)
      render json: { error: { code: "validation_error", message: e.message } }, status: :unprocessable_entity
    end

    def stale_object(_e)
      render json: { error: { code: "stale_object", message: "リソースが更新されています。再取得してください" } }, status: :conflict
    end

    def invalid_reference(_e)
      render json: { error: { code: "validation_error", message: "参照先が存在しません" } }, status: :unprocessable_entity
    end

    def conflict(e)
      render json: { error: { code: "conflict", message: e.message } }, status: :conflict
    end

    def set_request_id
      Thread.current[:request_id] = request.request_id
    end

    def paginate(scope)
      per_page = [params.fetch(:per_page, 25).to_i, 100].min
      pagy, records = pagy(scope, limit: per_page)
      {
        data: records,
        pagination: {
          page: pagy.page,
          per_page: pagy.limit,
          total_count: pagy.count,
          total_pages: pagy.pages
        }
      }
    end
  end
end
```

### 6.2 Api::AccountsController

```ruby
# app/controllers/api/accounts_controller.rb
module Api
  class AccountsController < BaseController
    def index
      render json: paginate(Account.order(created_at: :desc))
    end

    def show
      account = Account.find(params[:id])
      balance = account.fetch_balance
      render json: account.as_json.merge(balance: balance)
    end

    def sync
      Account.sync!
      render json: { message: "同期完了" }, status: :ok
    end
  end
end
```

### 6.3 Api::TransfersController

```ruby
# app/controllers/api/transfers_controller.rb
module Api
  class TransfersController < BaseController
    def index
      transfers = Transfer.all
        .by_status(params[:status])
        .by_date_range(params[:from_date], params[:to_date])
        .order(created_at: :desc)
      render json: paginate(transfers)
    end

    def show
      render json: Transfer.find(params[:id])
    end

    def create
      transfer = Transfer.find_or_create_idempotent!(transfer_params)
      status = transfer.previously_new_record? ? :created : :ok
      render json: transfer, status: status
    end

    private

    def transfer_params
      params.require(:transfer).permit(
        :app_request_id, :account_id,
        :destination_bank_code, :destination_branch_code,
        :destination_account_number, :destination_account_type,
        :destination_account_name, :amount, :transfer_date, :remarks
      )
    end
  end
end
```

### 6.4 Api::MetricsController

```ruby
# app/controllers/api/metrics_controller.rb
module Api
  class MetricsController < BaseController
    def show
      render json: {
        outbox_pending_depth: OutboxEvent.where(status: "pending").count,
        outbox_failed_depth: OutboxEvent.where(status: "failed").count,
        transfer_status: Transfer.group(:status).count
      }
    end
  end
end
```

### 6.5 Admin::BaseController

```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ActionController::Base
    include Pagy::Backend
    layout "admin"
  end
end
```

### 6.6 Admin::DashboardController

```ruby
# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < BaseController
    def show
      @transfer_counts = Transfer.group(:status).count
      @invoice_counts = Invoice.group(:status).count
      @outbox_pending = OutboxEvent.where(status: "pending").count
      @outbox_failed = OutboxEvent.where(status: "failed").count
    end
  end
end
```

### 6.7 Admin::TransfersController

```ruby
# app/controllers/admin/transfers_controller.rb
module Admin
  class TransfersController < BaseController
    def index
      transfers = Transfer.all.by_status(params[:status]).order(created_at: :desc)
      @pagy, @transfers = pagy(transfers)
    end

    def show
      @transfer = Transfer.find(params[:id])
      @outbox_events = OutboxEvent.where(
        aggregate_type: "Transfer", aggregate_id: @transfer.id_for_payload
      ).order(created_at: :desc)
    end
  end
end
```

### 6.8 Admin::InvoicesController

```ruby
# app/controllers/admin/invoices_controller.rb
module Admin
  class InvoicesController < BaseController
    def index
      invoices = Invoice.all.by_status(params[:status]).order(created_at: :desc)
      @pagy, @invoices = pagy(invoices)
    end

    def new
      @invoice = Invoice.new
    end

    def create
      @invoice = Invoice.new(invoice_params)
      if @invoice.save
        redirect_to admin_invoices_path, notice: "請求書を作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @invoice = Invoice.find(params[:id])
    end

    def update
      @invoice = Invoice.find(params[:id])
      if @invoice.update(invoice_params)
        redirect_to admin_invoices_path, notice: "請求書を更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Invoice.find(params[:id]).destroy!
      redirect_to admin_invoices_path, notice: "請求書を削除しました"
    end

    private

    def invoice_params
      params.require(:invoice).permit(:virtual_account_id, :amount, :description, :due_date)
    end
  end
end
```

### 6.9 Admin::ReconciliationsController

```ruby
# app/controllers/admin/reconciliations_controller.rb
module Admin
  class ReconciliationsController < BaseController
    def index
      @virtual_accounts = VirtualAccount.includes(:invoices, :incoming_transactions).all
    end
  end
end
```

### 6.10 Api::VirtualAccountsController

```ruby
# app/controllers/api/virtual_accounts_controller.rb
module Api
  class VirtualAccountsController < BaseController
    def index
      render json: paginate(VirtualAccount.order(created_at: :desc))
    end

    def create
      account = Account.find(params[:account_id])
      va = VirtualAccount.issue!(account: account, va_name: params[:va_name])
      render json: va, status: :created
    end
  end
end
```

### 6.11 Admin::OutboxEventsController

```ruby
# app/controllers/admin/outbox_events_controller.rb
module Admin
  class OutboxEventsController < BaseController
    def index
      events = OutboxEvent.all
      events = events.where(status: params[:status]) if params[:status].present?
      @pagy, @outbox_events = pagy(events.order(created_at: :desc))
    end

    def show
      @outbox_event = OutboxEvent.find(params[:id])
    end
  end
end
```

## 7. SunabarClient設計

```ruby
# app/clients/sunabar_client.rb
class SunabarClient
  BASE_URL = "https://api.sunabar.gmo-aozora.com".freeze
  TIMEOUT = 5

  class << self
    def instance
      @instance
    end

    def setup!
      @instance = new
    end
  end

  def initialize
    @personal_token = fetch_credential(:sunabar_personal_token)
    @corporate_token = fetch_credential(:sunabar_corporate_token)
    @personal_conn = build_connection(@personal_token)
    @corporate_conn = build_connection(@corporate_token)
  end

  def request_transfer(idempotency_key:, account_id:, **params)
    execute(:personal) do
      @personal_conn.post("/personal/v1/transfer/request") do |req|
        req.headers["x-idempotency-key"] = idempotency_key
        req.body = build_transfer_body(params)
      end
    end
  end

  def get_transfer_status(apply_no:)
    execute(:personal) do
      @personal_conn.get("/personal/v1/transfer/status", { applyNo: apply_no })
    end
  end

  def list_accounts
    execute(:personal) do
      @personal_conn.get("/personal/v1/accounts")
    end
  end

  def get_balance(account_id:)
    execute(:personal) do
      @personal_conn.get("/personal/v1/accounts/balances", { accountId: account_id })
    end
  end

  def list_transactions(va_id:)
    result = execute(:corporate) do
      @corporate_conn.get("/corporation/v1/va/transactions", { vaId: va_id })
    end
    result[:transactions]&.map { |t| parse_transaction(t) } || []
  end

  def issue_virtual_account(account_id:, va_name:)
    execute(:corporate) do
      @corporate_conn.post("/corporation/v1/va/issue") do |req|
        req.body = { vaTypeCode: "1", vaName: va_name }.to_json
      end
    end
  end

  private

  def execute(_auth_type)
    response = yield
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise SunabarErrors::TimeoutError, e.message
  rescue Faraday::ConnectionFailed => e
    raise SunabarErrors::ConnectionError, e.message
  end

  def build_connection(token)
    Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{token}"
      f.options.timeout = TIMEOUT
      f.options.open_timeout = TIMEOUT
    end
  end

  def handle_response(response)
    case response.status
    when 200..299
      response.body.deep_symbolize_keys
    when 400..499
      raise SunabarErrors::ClientError, "#{response.status}: #{response.body}"
    when 500..599
      raise SunabarErrors::ServerError, "#{response.status}: #{response.body}"
    else
      raise SunabarErrors::Error, "予期しないHTTPステータス: #{response.status}"
    end
  end

  def build_transfer_body(params)
    {
      accountId: params[:account_id],
      transferDesignatedDate: params[:transfer_date]&.strftime("%Y%m%d"),
      transferDateHolidayCode: "1",
      transfers: [{
        itemId: "1",
        transferAmount: params[:amount].to_s,
        beneficiaryBankCode: params[:destination_bank_code],
        beneficiaryBranchCode: params[:destination_branch_code],
        accountTypeCode: params[:destination_account_type] == "ordinary" ? "1" : "2",
        accountNumber: params[:destination_account_number],
        beneficiaryName: params[:destination_account_name]
      }]
    }.to_json
  end

  def parse_transaction(t)
    {
      transaction_id: t[:transactionId] || t["transactionId"],
      amount: parse_int(t[:amount] || t["amount"]),
      sender_name: t[:senderName] || t["senderName"],
      transaction_date: t[:transactionDate] || t["transactionDate"]
    }
  end

  def parse_int(val)
    val.is_a?(String) ? val.to_i : val
  end

  def fetch_credential(key)
    ENV[key.to_s.upcase] || Rails.application.credentials.dig(:sunabar, key)
  end
end
```

### 7.1 初期化

```ruby
# config/initializers/sunabar.rb
SunabarClient.setup!
```

```ruby
# config/initializers/circuit_breaker.rb
Rails.application.config.circuit_breaker = CircuitBreaker.new
```

## 8. JSON応答のシリアライゼーション

Transfer等のモデルで`as_json`をオーバーライドし、APIレスポンスに不要なカラムを除外する。

```ruby
# app/models/transfer.rb に追加
def as_json(options = {})
  super(options.reverse_merge(
    except: [:lock_version, :api_idempotency_key]
  ))
end
```

## 9. ログ設計

### 9.1 lograge設定

```ruby
# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    {
      request_id: event.payload[:request_id],
      remote_ip: event.payload[:remote_ip]
    }
  end
end
```

## 10. Docker設計

### 10.1 Dockerfile

```dockerfile
FROM ruby:3.4-slim

ENV RUBY_YJIT_ENABLE=1
ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT=development:test

RUN apt-get update -qq && \
    apt-get install -y build-essential default-libmysqlclient-dev git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN bundle exec rails assets:precompile

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### 10.2 compose.yml

```yaml
services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: rails_sunabar_development
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 3

  app:
    build: .
    command: bundle exec puma -C config/puma.rb
    environment:
      RUBY_YJIT_ENABLE: "1"
      DATABASE_URL: mysql2://root:password@db:3306/rails_sunabar_development
      RAILS_ENV: development
    ports:
      - "3000:3000"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/app

  worker:
    build: .
    command: bundle exec rails solid_queue:start
    environment:
      RUBY_YJIT_ENABLE: "1"
      DATABASE_URL: mysql2://root:password@db:3306/rails_sunabar_development
      RAILS_ENV: development
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/app

volumes:
  mysql_data:
```

## 11. bin/sunabar_probe

```ruby
#!/usr/bin/env ruby
# bin/sunabar_probe
require "net/http"
require "json"
require "uri"

token = ENV.fetch("SUNABAR_PERSONAL_TOKEN") { abort "SUNABAR_PERSONAL_TOKEN未設定" }
uri = URI("https://api.sunabar.gmo-aozora.com/personal/v1/accounts")

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.open_timeout = 5
http.read_timeout = 5

req = Net::HTTP::Get.new(uri)
req["Authorization"] = "Bearer #{token}"

res = http.request(req)
puts JSON.pretty_generate(
  { status: res.code, body: JSON.parse(res.body), timestamp: Time.now.iso8601 }
)
exit(res.code.to_i == 200 ? 0 : 1)
```

## 12. テスト設計(MECEロジックツリー)

```
テスト
├── 12.1 単体テスト(test/models/, test/handlers/)
│   ├── UT-TRF-01 Transfer.create_with_outbox!
│   ├── UT-TRF-02 Transfer冪等性(UNIQUE違反→既存返却)
│   ├── UT-TRF-04 HasStatusMachine遷移テスト(正常/異常)
│   ├── UT-TRF-05 SunabarStatusMapper全マッピング
│   ├── UT-REC-01 IncomingTransaction.upsert_from_sunabar!(重複吸収)
│   ├── UT-REC-03 Invoice#apply_payment(4状態遷移)
│   ├── UT-REL-01 OutboxEvent.pending_dispatchable(SKIP LOCKED)
│   ├── UT-REL-03 CircuitBreaker(CLOSED→OPEN→HALF_OPEN→CLOSED)
│   ├── UT-REL-04 OutboxEvent#backoff_seconds(指数バックオフ、上限)
│   ├── UT-REL-05 Transfer楽観的ロック(StaleObjectError)
│   ├── UT-REL-06 OutboxEvent#record_skip_attempt!(count据え置き)
│   ├── UT-NTF-02 EventProcessed二重処理防止
│   ├── UT-HND-01 SendToSunabar(成功/4xx/5xx/CB OPEN)
│   ├── UT-HND-02 CheckTransferStatus(各ステータスマッピング/still_in_flight)
│   └── UT-HND-03 ProcessNotification(初回/二重処理)
├── 12.2 結合テスト(test/integration/)
│   ├── IT-TRF-01 振込作成→Outbox→Relay→状態遷移の一連フロー
│   ├── IT-REC-01 消込バッチの一連フロー(明細取得→突合→状態更新)
│   └── IT-REL-02 二重リクエスト(同一app_request_id)テスト
├── 12.3 コントローラテスト(test/controllers/)
│   ├── CT-ACC-01 POST /api/accounts/sync
│   ├── CT-TRF-01 POST /api/transfers(201/200冪等)
│   ├── CT-TRF-02 GET /api/transfers/:id(200/404)
│   ├── CT-TRF-03 GET /api/transfers(フィルタ/ページネーション)
│   ├── CT-MET-01 GET /api/metrics
│   └── CT-ERR-01 各エラーレスポンス(404/409/422/500)
└── 12.4 E2Eテスト(test/system/)
    ├── E2E-ADM-01 ダッシュボード表示
    ├── E2E-ADM-02 振込一覧フィルタ操作
    ├── E2E-REC-02 請求書CRUD操作
    └── E2E-ADM-04 Outboxモニタ表示
```

### 12.1 WebMockベースのモック戦略

```ruby
# test/support/mock_sunabar.rb
module MockSunabar
  def stub_request_transfer(apply_no: "APL-001")
    stub_request(:post, %r{/personal/v1/transfer/request})
      .to_return(
        status: 200,
        body: { applyNo: apply_no }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_transfer_status(status: "Settled")
    stub_request(:get, %r{/personal/v1/transfer/status})
      .to_return(
        status: 200,
        body: { status: status }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_list_accounts
    stub_request(:get, %r{/personal/v1/accounts})
      .to_return(
        status: 200,
        body: { accounts: [{ accountId: "ACC-1", accountNumber: "1234567", branchCode: "101", accountName: "テスト" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_sunabar_error(status:)
    stub_request(:any, %r{api\.sunabar})
      .to_return(status: status, body: { error: "test" }.to_json)
  end
end
```

### 12.2 Fixture設計

```yaml
# test/fixtures/accounts.yml
main_account:
  id: <%= ["0" * 30 + "01"].pack("H*").inspect %>
  sunabar_account_id: "ACC-001"
  account_number: "1234567"
  branch_code: "101"
  account_name: "テスト口座"

# test/fixtures/transfers.yml
pending_transfer:
  id: <%= ["0" * 30 + "11"].pack("H*").inspect %>
  account: main_account
  app_request_id: "REQ-001"
  api_idempotency_key: "KEY-001"
  status: "pending"
  destination_bank_code: "0310"
  destination_branch_code: "101"
  destination_account_number: "7654321"
  destination_account_type: "ordinary"
  destination_account_name: "テスト タロウ"
  amount: 10000
  transfer_date: "2026-06-20"
```

## 13. トレーサビリティ対応表(基本設計→詳細設計→テスト)

| BD ID | DD ID | 詳細設計要素 | テストID | 確認 |
|-------|-------|-------------|----------|------|
| BD-ACC-01 | DD-ACC-01 | Account.sync! | UT-ACC-01 | ☐ |
| BD-ACC-02 | DD-ACC-02 | Account#fetch_balance | UT-ACC-02 | ☐ |
| BD-ACC-03 | DD-ACC-03 | VirtualAccount.issue! | UT-ACC-03 | ☐ |
| BD-ACC-04 | DD-ACC-04 | VirtualAccount scope | UT-ACC-04 | ☐ |
| BD-TRF-01 | DD-TRF-01 | Transfer.create_with_outbox! | UT-TRF-01, CT-TRF-01 | ☐ |
| BD-TRF-02 | DD-TRF-02 | TransfersController#show | CT-TRF-02 | ☐ |
| BD-TRF-03 | DD-TRF-03 | Transfer.by_status/by_date_range | UT-TRF-03, CT-TRF-03 | ☐ |
| BD-TRF-04 | DD-TRF-04 | HasStatusMachine#transition_to! | UT-TRF-04 | ☐ |
| BD-TRF-05 | DD-TRF-05 | CheckTransferStatus#call | UT-HND-02 | ☐ |
| BD-REC-01 | DD-REC-01 | IncomingTransaction.upsert_from_sunabar! | UT-REC-01 | ☐ |
| BD-REC-02 | DD-REC-02 | Admin::InvoicesController CRUD | E2E-REC-02 | ☐ |
| BD-REC-03 | DD-REC-03 | Invoice#apply_payment + ReconciliationMatch | UT-REC-03, IT-REC-01 | ☐ |
| BD-REC-04 | DD-REC-04 | Outbox ReconciliationCompleted等 | UT-REC-04 | ☐ |
| BD-NTF-01 | DD-NTF-01 | ProcessNotification#call | UT-HND-03 | ☐ |
| BD-NTF-02 | DD-NTF-02 | EventProcessed.mark_processed! | UT-NTF-02 | ☐ |
| BD-REL-01 | DD-REL-01 | OutboxRelayJob(per-event tx) | UT-REL-01, IT-TRF-01 | ☐ |
| BD-REL-02 | DD-REL-02 | Transfer冪等性(insert-first) | UT-TRF-02, IT-REL-02 | ☐ |
| BD-REL-03 | DD-REL-03 | CircuitBreaker PORO | UT-REL-03 | ☐ |
| BD-REL-04 | DD-REL-04 | OutboxEvent#backoff_seconds | UT-REL-04 | ☐ |
| BD-REL-05 | DD-REL-05 | lock_version + StaleObjectError | UT-REL-05 | ☐ |
| BD-REL-06 | DD-REL-06 | OutboxEvent#record_skip_attempt! | UT-REL-06 | ☐ |
| BD-OPS-01 | DD-OPS-01 | compose.yml(app/worker/db) | (手動確認) | ☐ |
| BD-OPS-02 | DD-OPS-02 | ENV RUBY_YJIT_ENABLE=1 | (手動確認) | ☐ |
| BD-OPS-03 | DD-OPS-03 | GET /up | (手動確認) | ☐ |
| BD-OPS-04 | DD-OPS-04 | lograge JSON + request_id | UT-OPS-04 | ☐ |
| BD-OPS-05 | DD-OPS-05 | MetricsController#show | CT-MET-01 | ☐ |
| BD-OPS-06 | DD-OPS-06 | bin/sunabar_probe | (手動確認) | ☐ |
| BD-QA-01 | DD-QA-01 | SimpleCov + CI coverage check | (CI確認) | ☐ |
| BD-QA-06 | DD-QA-06 | MockSunabar(WebMock) | (テスト実行確認) | ☐ |
| BD-SEC-01 | DD-SEC-01 | credentials + ENV fallback | UT-SEC-01 | ☐ |
| BD-SEC-02 | DD-SEC-02 | personal/corporate token分離 | UT-SEC-02 | ☐ |
| BD-CI-01 | DD-CI-01 | lefthook.yml(parallel) | (CI確認) | ☐ |
| BD-CI-02 | DD-CI-02 | .github/workflows/ci.yml | (CI確認) | ☐ |
| BD-ADM-01 | DD-ADM-01 | DashboardController(load_async) | E2E-ADM-01 | ☐ |
| BD-ADM-02 | DD-ADM-02 | Admin::TransfersController | E2E-ADM-02 | ☐ |
| BD-ADM-03 | DD-ADM-03 | Admin::ReconciliationsController | (実装確認) | ☐ |
| BD-ADM-04 | DD-ADM-04 | Admin::OutboxEventsController | E2E-ADM-04 | ☐ |
