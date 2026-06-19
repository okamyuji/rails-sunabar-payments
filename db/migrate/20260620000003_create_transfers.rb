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
      t.string :destination_account_type,
               limit: 10,
               null: false,
               default: "ordinary"
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
    add_index :transfers, %i[status created_at]
    add_foreign_key :transfers, :accounts, column: :account_id
  end
end
