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

ActiveRecord::Schema[7.1].define(version: 2026_10_18_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "tracking_event_type", ["inventory_presence", "price_tracker"]

  create_table "brands", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "products", force: :cascade do |t|
    t.string "name"
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["name", "brand_id"], name: "index_products_on_name_and_brand_id", unique: true
  end

  create_table "stores", force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tracking_events", force: :cascade do |t|
    t.boolean "inventory_present"
    t.bigint "product_id", null: false
    t.bigint "store_id", null: false
    t.datetime "event_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.enum "event_type", default: "inventory_presence", null: false, enum_type: "tracking_event_type"
    t.jsonb "value", null: false
    t.index ["product_id"], name: "index_tracking_events_on_product_id"
    t.index ["store_id", "product_id", "event_type", "event_time", "id"], name: "index_tracking_events_on_latest_observation", order: { event_time: :desc, id: :desc }
    t.index ["store_id"], name: "index_tracking_events_on_store_id"
    t.check_constraint "event_type <> 'inventory_presence'::tracking_event_type OR (NOT value ? 'present'::text AND\nCASE\n    WHEN jsonb_typeof(value -> 'quantity'::text) = 'number'::text THEN ((value ->> 'quantity'::text)::numeric) = trunc((value ->> 'quantity'::text)::numeric)\n    ELSE false\nEND) IS TRUE", name: "tracking_events_inventory_quantity"
    t.check_constraint "event_type <> 'price_tracker'::tracking_event_type OR (\nCASE\n    WHEN jsonb_typeof(value -> 'amount'::text) = 'number'::text THEN ((value ->> 'amount'::text)::numeric) >= 0::numeric\n    ELSE false\nEND AND jsonb_typeof(value -> 'currency'::text) = 'string'::text AND char_length(value ->> 'currency'::text) = 3 AND (value ->> 'currency'::text) ~ '^[A-Z]{3}$'::text) IS TRUE", name: "tracking_events_price_payload"
    t.check_constraint "jsonb_typeof(value) = 'object'::text", name: "tracking_events_value_structure"
  end

  add_foreign_key "products", "brands"
  add_foreign_key "tracking_events", "products"
  add_foreign_key "tracking_events", "stores"
end
