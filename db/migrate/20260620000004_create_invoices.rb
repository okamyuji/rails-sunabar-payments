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
