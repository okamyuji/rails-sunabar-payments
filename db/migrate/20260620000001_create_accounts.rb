class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: false do |t|
      t.binary :id, limit: 16, null: false
      t.string :sunabar_account_id, limit: 64, null: false
      t.string :account_number, limit: 20, null: false
      t.string :branch_code, limit: 10, null: false
      t.string :account_name, limit: 128
      t.datetime :synced_at, precision: 6
      t.timestamps precision: 6
    end

    execute "ALTER TABLE accounts ADD PRIMARY KEY (id)"
    add_index :accounts, :sunabar_account_id, unique: true
  end
end
