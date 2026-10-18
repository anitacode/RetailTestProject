class AddValueToTrackingEvents < ActiveRecord::Migration[7.1]
  def up
    add_column :tracking_events, :value, :jsonb,
      default: { "type" => "null", "value" => nil }, null: false

    execute <<~SQL
      UPDATE tracking_events
      SET value = jsonb_build_object(
        'type', CASE WHEN inventory_present IS NULL THEN 'null' ELSE 'boolean' END,
        'value', inventory_present
      )
      WHERE type = 'inventory_presence'
    SQL

    add_check_constraint :tracking_events, <<~SQL.squish, name: "tracking_events_value_structure"
      jsonb_typeof(value) = 'object'
      AND value ? 'type'
      AND value ? 'value'
      AND jsonb_typeof(value -> 'type') = 'string'
    SQL
  end

  def down
    remove_check_constraint :tracking_events, name: "tracking_events_value_structure"
    remove_column :tracking_events, :value
  end
end
