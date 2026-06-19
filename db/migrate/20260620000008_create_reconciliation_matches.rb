class CreateReconciliationMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_matches, id: false do |t|
      t.binary :incoming_transaction_id, limit: 16, null: false
      t.binary :invoice_id, limit: 16, null: false
      t.bigint :applied_amount, null: false
      t.datetime :created_at, precision: 6, null: false
    end

    execute "ALTER TABLE reconciliation_matches ADD PRIMARY KEY (incoming_transaction_id, invoice_id)"
    add_foreign_key :reconciliation_matches,
                    :incoming_transactions,
                    column: :incoming_transaction_id
    add_foreign_key :reconciliation_matches, :invoices, column: :invoice_id
    add_index :reconciliation_matches, :invoice_id
  end
end
