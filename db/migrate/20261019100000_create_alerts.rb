class CreateAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :alerts do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :previous_event, null: false, foreign_key: { to_table: :tracking_events, on_delete: :cascade }
      t.references :triggering_event, null: false, index: { unique: true }, foreign_key: { to_table: :tracking_events, on_delete: :cascade }
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :alerts, [:brand_id, :observed_at, :id], order: { observed_at: :desc, id: :desc }
    add_check_constraint :alerts, "previous_event_id <> triggering_event_id", name: "alerts_distinct_observations"
  end
end
