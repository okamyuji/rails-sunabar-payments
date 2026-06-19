class ReconciliationMatch < ApplicationRecord
  self.primary_key = %i[incoming_transaction_id invoice_id]
  self.record_timestamps = false

  belongs_to :incoming_transaction
  belongs_to :invoice

  validates :applied_amount, numericality: { greater_than: 0 }
end
