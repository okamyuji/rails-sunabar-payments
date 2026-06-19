class Transfer < ApplicationRecord
  uuid_primary_key
  include HasStatusMachine
  include Outboxable

  attribute :account_id, :uuid_binary

  belongs_to :account

  STATUSES = %w[
    pending
    requested
    awaiting_approval
    approved
    settled
    failed
  ].freeze
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
  scope :by_date_range,
        ->(from, to) do
          relation = all
          relation = relation.where(transfer_date: from..) if from
          relation = relation.where(transfer_date: ..to) if to
          relation
        end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def self.create_with_outbox!(params)
    transaction do
      transfer = create!(params)
      transfer.publish_outbox_event!(
        event_type: "TransferRequested",
        payload: {
          transfer_id: transfer.id_for_payload
        }
      )
      transfer
    end
  end

  # 冪等性: insert-first方式。UNIQUE違反時に既存レコードを返す(TOCTOU排除)
  # RecordNotUnique(DB制約) と RecordInvalid(ARバリデーション) の両方をハンドリング
  def self.find_or_create_idempotent!(params)
    create_with_outbox!(params)
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?("app_request_id")
    existing = find_by!(app_request_id: params[:app_request_id])
    verify_idempotent_ownership!(existing, params)
    existing
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:app_request_id, :taken)
    existing = find_by!(app_request_id: params[:app_request_id])
    verify_idempotent_ownership!(existing, params)
    existing
  end

  def self.verify_idempotent_ownership!(existing, params)
    return unless params[:account_id].present?

    unless existing.account_id == params[:account_id]
      raise ActiveRecord::RecordNotFound, "app_request_idが別のアカウントに属しています"
    end
  end

  private

  def set_defaults
    self.api_idempotency_key ||= SecureRandom.uuid
    self.transfer_date ||= Time.current.in_time_zone("Asia/Tokyo").to_date
  end
end
