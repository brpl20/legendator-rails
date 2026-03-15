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

ActiveRecord::Schema[8.1].define(version: 2026_03_15_024301) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount_brl", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.string "pix_copia_e_cola"
    t.text "pix_qr_code_base64"
    t.string "pix_txid"
    t.integer "status", default: 0
    t.bigint "translation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pix_txid"], name: "index_payments_on_pix_txid", unique: true
    t.index ["translation_id"], name: "index_payments_on_translation_id"
  end

  create_table "translations", force: :cascade do |t|
    t.string "access_token", null: false
    t.decimal "cost_ai", precision: 10, scale: 6, default: "0.0"
    t.decimal "cost_ai_brl", precision: 10, scale: 2, default: "0.0"
    t.decimal "cost_user", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "model_used", default: "gpt-4.1-mini"
    t.string "original_filename", null: false
    t.float "processing_time"
    t.integer "status", default: 0
    t.integer "subtitle_count", default: 0
    t.string "target_language", default: "pt-BR"
    t.integer "tokens_input", default: 0
    t.integer "tokens_output", default: 0
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_translations_on_access_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "payments", "translations"
end
