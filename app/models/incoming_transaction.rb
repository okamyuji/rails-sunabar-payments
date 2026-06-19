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
