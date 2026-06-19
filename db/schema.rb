# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_20_000008) do
  create_table "accounts",
               id: {
                 type: :binary,
                 limit: 16
               },
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.string "account_name", limit: 128
    t.string "account_number", limit: 20, null: false
    t.string "branch_code", limit: 10, null: false
    t.datetime "created_at", null: false
    t.string "sunabar_account_id", limit: 64, null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["sunabar_account_id"],
            name: "index_accounts_on_sunabar_account_id",
            unique: true
  end

  create_table "event_processed",
               primary_key: %w[outbox_event_id consumer],
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.string "consumer", limit: 64, null: false
    t.bigint "outbox_event_id", null: false
    t.datetime "processed_at", null: false
  end

  create_table "incoming_transactions",
               id: {
                 type: :binary,
                 limit: 16
               },
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.bigint "amount", null: false
    t.datetime "created_at", null: false
    t.string "sender_name", limit: 128
    t.string "sunabar_transaction_id", limit: 64, null: false
    t.date "transaction_date", null: false
    t.binary "virtual_account_id", limit: 16, null: false
    t.index ["sunabar_transaction_id"],
            name: "index_incoming_transactions_on_sunabar_transaction_id",
            unique: true
    t.index ["virtual_account_id"],
            name: "index_incoming_transactions_on_virtual_account_id"
  end

  create_table "invoices",
               id: {
                 type: :binary,
                 limit: 16
               },
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.bigint "amount", null: false
    t.datetime "created_at", null: false
    t.string "description", limit: 256
    t.date "due_date"
    t.integer "lock_version", default: 0, null: false
    t.bigint "paid_amount", default: 0, null: false
    t.string "status", limit: 20, default: "open", null: false
    t.datetime "updated_at", null: false
    t.binary "virtual_account_id", limit: 16, null: false
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["virtual_account_id"], name: "index_invoices_on_virtual_account_id"
  end

  create_table "outbox_events",
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.string "aggregate_id", limit: 64, null: false
    t.string "aggregate_type", limit: 64, null: false
    t.integer "attempt_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "event_type", limit: 128, null: false
    t.text "last_error"
    t.integer "max_attempts", default: 10, null: false
    t.datetime "next_attempt_at", null: false
    t.json "payload", null: false
    t.datetime "sent_at"
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["aggregate_type"], name: "index_outbox_events_on_aggregate_type"
    t.index ["event_type"], name: "index_outbox_events_on_event_type"
    t.index %w[status next_attempt_at],
            name: "index_outbox_events_on_status_and_next_attempt_at"
  end

  create_table "reconciliation_matches",
               primary_key: %w[incoming_transaction_id invoice_id],
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.bigint "applied_amount", null: false
    t.datetime "created_at", null: false
    t.binary "incoming_transaction_id", limit: 16, null: false
    t.binary "invoice_id", limit: 16, null: false
    t.index ["invoice_id"], name: "index_reconciliation_matches_on_invoice_id"
  end

  create_table "transfers",
               id: {
                 type: :binary,
                 limit: 16
               },
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.binary "account_id", limit: 16, null: false
    t.bigint "amount", null: false
    t.string "api_idempotency_key", limit: 36, null: false
    t.string "app_request_id", limit: 64, null: false
    t.datetime "created_at", null: false
    t.string "destination_account_name", limit: 128, null: false
    t.string "destination_account_number", limit: 20, null: false
    t.string "destination_account_type",
             limit: 10,
             default: "ordinary",
             null: false
    t.string "destination_bank_code", limit: 10, null: false
    t.string "destination_branch_code", limit: 10, null: false
    t.text "last_error"
    t.integer "lock_version", default: 0, null: false
    t.string "remarks", limit: 128
    t.string "status", limit: 20, default: "pending", null: false
    t.string "sunabar_apply_no", limit: 64
    t.date "transfer_date", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_transfers_on_account_id"
    t.index ["api_idempotency_key"],
            name: "index_transfers_on_api_idempotency_key",
            unique: true
    t.index ["app_request_id"],
            name: "index_transfers_on_app_request_id",
            unique: true
    t.index %w[status created_at],
            name: "index_transfers_on_status_and_created_at"
    t.index ["status"], name: "index_transfers_on_status"
  end

  create_table "virtual_accounts",
               id: {
                 type: :binary,
                 limit: 16
               },
               charset: "utf8mb4",
               collation: "utf8mb4_0900_ai_ci",
               force: :cascade do |t|
    t.binary "account_id", limit: 16, null: false
    t.datetime "created_at", null: false
    t.string "sunabar_va_id", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.string "va_name", limit: 128
    t.string "va_number", limit: 20, null: false
    t.index ["account_id"], name: "index_virtual_accounts_on_account_id"
    t.index ["sunabar_va_id"],
            name: "index_virtual_accounts_on_sunabar_va_id",
            unique: true
  end

  add_foreign_key "event_processed", "outbox_events"
  add_foreign_key "incoming_transactions", "virtual_accounts"
  add_foreign_key "invoices", "virtual_accounts"
  add_foreign_key "reconciliation_matches", "incoming_transactions"
  add_foreign_key "reconciliation_matches", "invoices"
  add_foreign_key "transfers", "accounts"
  add_foreign_key "virtual_accounts", "accounts"
end
