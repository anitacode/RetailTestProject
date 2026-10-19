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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_170000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "tracking_event_type", ["inventory_presence", "price_tracker"]

  create_table "alerts", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "store_id", null: false
    t.bigint "product_id", null: false
    t.bigint "previous_event_id", null: false
    t.bigint "triggering_event_id", null: false
    t.datetime "observed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "seen_at"
    t.string "alert_type", default: "alert_no_inventory", null: false
    t.index ["brand_id", "observed_at", "id"], name: "index_alerts_on_brand_id_and_observed_at_and_id", order: { observed_at: :desc, id: :desc }
    t.index ["brand_id"], name: "index_alerts_on_brand_id"
    t.index ["previous_event_id"], name: "index_alerts_on_previous_event_id"
    t.index ["product_id"], name: "index_alerts_on_product_id"
    t.index ["store_id"], name: "index_alerts_on_store_id"
    t.index ["triggering_event_id"], name: "index_alerts_on_triggering_event_id", unique: true
    t.check_constraint "alert_type::text = ANY (ARRAY['alert_no_inventory'::character varying::text, 'alert_price_change'::character varying::text])", name: "alerts_valid_type"
    t.check_constraint "previous_event_id <> triggering_event_id", name: "alerts_distinct_observations"
  end

  create_table "brands", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contacts", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.jsonb "setup", default: {"alert_no_inventory" => false, "alert_price_change" => false}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_contacts_on_brand_id"
    t.check_constraint "COALESCE(jsonb_typeof(setup) = 'object'::text AND setup ?& ARRAY['alert_no_inventory'::text, 'alert_price_change'::text] AND jsonb_typeof(setup -> 'alert_no_inventory'::text) = 'boolean'::text AND jsonb_typeof(setup -> 'alert_price_change'::text) = 'boolean'::text AND (setup - 'alert_no_inventory'::text - 'alert_price_change'::text) = '{}'::jsonb, false)", name: "contacts_setup_booleans"
    t.check_constraint "btrim(name::text) <> ''::text", name: "contacts_name_present"
    t.check_constraint "email IS NOT NULL OR phone IS NOT NULL", name: "contacts_have_channel"
    t.check_constraint "email IS NULL OR email::text ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'::text", name: "contacts_email_format"
    t.check_constraint "phone IS NULL OR phone::text ~ '^[+][1-9][0-9]{7,14}$'::text", name: "contacts_phone_format"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
    t.index ["created_at", "id"], name: "index_good_job_batches_on_created_at_and_id", order: :desc
    t.index ["finished_at"], name: "index_good_job_batches_on_finished_at", where: "(finished_at IS NOT NULL)"
  end

  create_table "good_job_concurrency_claims", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "job_id", null: false
    t.uuid "locked_by_id"
    t.integer "state", limit: 2, null: false
    t.text "key", null: false
    t.index ["job_id"], name: "index_good_job_concurrency_claims_on_job_id"
    t.index ["key", "job_id"], name: "index_good_job_concurrency_claims_on_key_and_job_id", unique: true
    t.index ["key", "state", "created_at"], name: "index_good_job_concurrency_claims_for_promotion"
    t.index ["locked_by_id"], name: "index_good_job_concurrency_claims_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
    t.index ["scheduled_at"], name: "index_good_job_executions_on_scheduled_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.integer "lock_type", limit: 2
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id_unfinished", where: "((batch_callback_id IS NOT NULL) AND (finished_at IS NULL))"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id_unfinished", where: "((batch_id IS NOT NULL) AND (finished_at IS NULL))"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["created_at"], name: "index_good_jobs_on_created_at"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, order: { cron_at: "DESC NULLS LAST" }, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_on_discarded", order: :desc, where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["id"], name: "index_good_jobs_on_unfinished_or_errored", where: "((finished_at IS NULL) OR (error IS NOT NULL))"
    t.index ["job_class", "finished_at"], name: "index_good_jobs_on_discarded_job_class", where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_for_candidate_dequeue_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_on_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["queue_name", "priority", "created_at"], name: "index_good_jobs_dequeue_by_queue", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "priority", "scheduled_at"], name: "index_good_jobs_dequeue_by_queue_scheduled_at", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at", "id"], name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["queue_name"], name: "index_good_jobs_on_queue_name"
    t.index ["scheduled_at", "queue_name"], name: "index_good_jobs_on_scheduled_at_and_queue_name"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.bigint "contact_id", null: false
    t.bigint "alert_id"
    t.bigint "tracking_event_id"
    t.string "kind", null: false
    t.string "channel", null: false
    t.string "destination", null: false
    t.text "body", null: false
    t.datetime "simulated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_id", "contact_id", "channel"], name: "unique_inventory_contact_delivery", unique: true, where: "(alert_id IS NOT NULL)"
    t.index ["alert_id"], name: "index_notification_deliveries_on_alert_id"
    t.index ["contact_id"], name: "index_notification_deliveries_on_contact_id"
    t.index ["tracking_event_id", "contact_id", "channel"], name: "unique_price_contact_delivery", unique: true, where: "(tracking_event_id IS NOT NULL)"
    t.index ["tracking_event_id"], name: "index_notification_deliveries_on_tracking_event_id"
    t.check_constraint "channel::text = ANY (ARRAY['sms'::character varying::text, 'email'::character varying::text])", name: "notification_delivery_channel"
    t.check_constraint "kind::text = 'alert_no_inventory'::text AND alert_id IS NOT NULL AND tracking_event_id IS NULL OR kind::text = 'alert_price_change'::text AND tracking_event_id IS NOT NULL AND alert_id IS NULL", name: "notification_delivery_source"
  end

  create_table "products", force: :cascade do |t|
    t.string "name"
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["name", "brand_id"], name: "index_products_on_name_and_brand_id", unique: true
  end

  create_table "sms_deliveries", force: :cascade do |t|
    t.bigint "alert_id", null: false
    t.string "phone_number", null: false
    t.text "body", null: false
    t.datetime "simulated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_id"], name: "index_sms_deliveries_on_alert_id", unique: true
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
    t.boolean "alert_eligible", default: true, null: false
    t.boolean "price_alert_eligible", default: true, null: false
    t.index ["product_id"], name: "index_tracking_events_on_product_id"
    t.index ["store_id", "product_id", "event_type", "event_time", "id"], name: "index_tracking_events_on_latest_observation", order: { event_time: :desc, id: :desc }
    t.index ["store_id"], name: "index_tracking_events_on_store_id"
    t.check_constraint "event_type <> 'inventory_presence'::tracking_event_type OR (NOT value ? 'present'::text AND\nCASE\n    WHEN jsonb_typeof(value -> 'quantity'::text) = 'number'::text THEN ((value ->> 'quantity'::text)::numeric) = trunc((value ->> 'quantity'::text)::numeric)\n    ELSE false\nEND) IS TRUE", name: "tracking_events_inventory_quantity"
    t.check_constraint "event_type <> 'price_tracker'::tracking_event_type OR (\nCASE\n    WHEN jsonb_typeof(value -> 'amount'::text) = 'number'::text THEN ((value ->> 'amount'::text)::numeric) >= 0::numeric\n    ELSE false\nEND AND jsonb_typeof(value -> 'currency'::text) = 'string'::text AND char_length(value ->> 'currency'::text) = 3 AND (value ->> 'currency'::text) ~ '^[A-Z]{3}$'::text) IS TRUE", name: "tracking_events_price_payload"
    t.check_constraint "jsonb_typeof(value) = 'object'::text", name: "tracking_events_value_structure"
  end

  add_foreign_key "alerts", "brands"
  add_foreign_key "alerts", "products"
  add_foreign_key "alerts", "stores"
  add_foreign_key "alerts", "tracking_events", column: "previous_event_id", on_delete: :cascade
  add_foreign_key "alerts", "tracking_events", column: "triggering_event_id", on_delete: :cascade
  add_foreign_key "contacts", "brands"
  add_foreign_key "notification_deliveries", "alerts", on_delete: :cascade
  add_foreign_key "notification_deliveries", "contacts", on_delete: :cascade
  add_foreign_key "notification_deliveries", "tracking_events", on_delete: :cascade
  add_foreign_key "products", "brands"
  add_foreign_key "sms_deliveries", "alerts", on_delete: :cascade
  add_foreign_key "tracking_events", "products"
  add_foreign_key "tracking_events", "stores"
end
