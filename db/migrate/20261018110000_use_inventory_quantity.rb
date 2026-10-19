class UseInventoryQuantity < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :tracking_events, name: "tracking_events_inventory_payload"
    remove_check_constraint :tracking_events, name: "tracking_events_inventory_quantity"

    # Legacy true means a placeholder count of one, not a measured quantity.
    execute <<~SQL
      UPDATE tracking_events
      SET value = (value - 'present') || jsonb_build_object('quantity',
        COALESCE(value -> 'quantity', CASE WHEN value -> 'present' = 'true'::jsonb THEN '1'::jsonb ELSE '0'::jsonb END))
      WHERE event_type = 'inventory_presence'
    SQL

    add_check_constraint :tracking_events, <<~SQL.squish, name: "tracking_events_inventory_quantity"
      event_type <> 'inventory_presence' OR (
        NOT (value ? 'present') AND
        CASE WHEN jsonb_typeof(value -> 'quantity') = 'number'
          THEN (value ->> 'quantity')::numeric = trunc((value ->> 'quantity')::numeric)
          ELSE FALSE
        END
      ) IS TRUE
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Legacy presence observations have been converted to quantities"
  end
end
