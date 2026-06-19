class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events do |t|
      t.string :aggregate_type, limit: 64, null: false
      t.string :aggregate_id, limit: 64, null: false
      t.string :event_type, limit: 128, null: false
      t.json :payload, null: false
      t.string :status, limit: 20, null: false, default: "pending"
      t.integer :attempt_count, null: false, default: 0
      t.integer :max_attempts, null: false, default: 10
      t.datetime :next_attempt_at, precision: 6, null: false
      t.text :last_error
      t.datetime :sent_at, precision: 6
      t.timestamps precision: 6
    end

    add_index :outbox_events, %i[status next_attempt_at]
    add_index :outbox_events, :aggregate_type
    add_index :outbox_events, :event_type
  end
end
