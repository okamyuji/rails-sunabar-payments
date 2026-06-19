class CreateEventProcessed < ActiveRecord::Migration[8.1]
  def change
    create_table :event_processed, id: false do |t|
      t.bigint :outbox_event_id, null: false
      t.string :consumer, limit: 64, null: false
      t.datetime :processed_at, precision: 6, null: false
    end

    execute "ALTER TABLE event_processed ADD PRIMARY KEY (outbox_event_id, consumer)"
    add_foreign_key :event_processed, :outbox_events, column: :outbox_event_id
  end
end
