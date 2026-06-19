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
