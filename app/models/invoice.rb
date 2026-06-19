class Invoice < ApplicationRecord
  uuid_primary_key
  include Outboxable

  attribute :virtual_account_id, :uuid_binary

  belongs_to :virtual_account
  has_many :reconciliation_matches, dependent: :destroy

  STATUSES = %w[open partial cleared excess].freeze

  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :pending_reconciliation, -> { where(status: %w[open partial]) }

  # 消込状態は金額から決定的に導出されるため、HasStatusMachineは使わない
  # update!とOutboxイベント発行を同一トランザクションで原子的に実行
  def apply_payment(payment_amount)
    new_paid = paid_amount + payment_amount
    new_status = determine_status(new_paid)

    transaction do
      update!(paid_amount: new_paid, status: new_status)

      event_type =
        case new_status
        when "cleared"
          "ReconciliationCompleted"
        when "excess"
          "ReconciliationExcess"
        when "partial"
          "ReconciliationPartial"
        end

      if event_type
        publish_outbox_event!(
          event_type: event_type,
          payload: {
            invoice_id: id_for_payload
          }
        )
      end
    end
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
