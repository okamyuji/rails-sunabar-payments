class ReconcileJob < ApplicationJob
  queue_as :default

  def perform
    VirtualAccount.find_each { |va| reconcile_va(va) }
  end

  private

  def reconcile_va(va)
    client = SunabarClient.instance
    transactions = client.list_transactions(va_id: va.sunabar_va_id)
    IncomingTransaction.upsert_from_sunabar!(va: va, transactions: transactions)

    unmatched =
      IncomingTransaction
        .where(virtual_account_id: va.id)
        .left_joins(:reconciliation_matches)
        .where(reconciliation_matches: { incoming_transaction_id: nil })

    unmatched.find_each do |txn|
      invoice =
        va.invoices.pending_reconciliation.order(:due_date, :created_at).first
      break unless invoice

      Invoice.transaction do
        locked_invoice = Invoice.lock.find(invoice.id)
        ReconciliationMatch.create!(
          incoming_transaction: txn,
          invoice: locked_invoice,
          applied_amount: txn.amount,
          created_at: Time.current
        )
        locked_invoice.apply_payment(txn.amount)
      end
    end
  rescue SunabarErrors::Error, ActiveRecord::ActiveRecordError => e
    Rails.logger.error(
      {
        event: "reconcile_failed",
        va_id: va.id_for_payload,
        error: e.message
      }.to_json
    )
  end
end
