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
    add_foreign_key :incoming_transactions,
                    :virtual_accounts,
                    column: :virtual_account_id
  end
end
