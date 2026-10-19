class CreateContactsAndNotificationDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :contacts do |t|
      t.references :brand, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.jsonb :setup, null: false, default: { alert_no_inventory: false, alert_price_change: false }
      t.timestamps
    end
    add_check_constraint :contacts, "btrim(name) <> ''", name: "contacts_name_present"
    add_check_constraint :contacts, "email IS NOT NULL OR phone IS NOT NULL", name: "contacts_have_channel"
    add_check_constraint :contacts, "email IS NULL OR email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'", name: "contacts_email_format"
    add_check_constraint :contacts, "phone IS NULL OR phone ~ '^[+][1-9][0-9]{7,14}$'", name: "contacts_phone_format"
    add_check_constraint :contacts, <<~SQL.squish, name: "contacts_setup_booleans"
      COALESCE(jsonb_typeof(setup) = 'object'
        AND setup ?& ARRAY['alert_no_inventory', 'alert_price_change']
        AND jsonb_typeof(setup -> 'alert_no_inventory') = 'boolean'
        AND jsonb_typeof(setup -> 'alert_price_change') = 'boolean'
        AND (setup - 'alert_no_inventory' - 'alert_price_change') = '{}'::jsonb, false)
    SQL

    create_table :notification_deliveries do |t|
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :alert, foreign_key: { on_delete: :cascade }
      t.references :tracking_event, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :channel, null: false
      t.string :destination, null: false
      t.text :body, null: false
      t.datetime :simulated_at, null: false
      t.timestamps
    end
    add_index :notification_deliveries, [:alert_id, :contact_id, :channel], unique: true,
                                                                            where: "alert_id IS NOT NULL", name: "unique_inventory_contact_delivery"
    add_index :notification_deliveries, [:tracking_event_id, :contact_id, :channel], unique: true,
                                                                                     where: "tracking_event_id IS NOT NULL", name: "unique_price_contact_delivery"
    add_check_constraint :notification_deliveries, "channel IN ('sms', 'email')", name: "notification_delivery_channel"
    add_check_constraint :notification_deliveries, <<~SQL.squish, name: "notification_delivery_source"
      (kind = 'alert_no_inventory' AND alert_id IS NOT NULL AND tracking_event_id IS NULL)
      OR (kind = 'alert_price_change' AND tracking_event_id IS NOT NULL AND alert_id IS NULL)
    SQL
  end
end
