class EnforceInventoryQuantity < ActiveRecord::Migration[7.1]
  def change
    add_check_constraint :tracking_events, <<~SQL.squish, name: "tracking_events_inventory_quantity"
      event_type <> 'inventory_presence' OR NOT (value ? 'quantity') OR (
        CASE WHEN jsonb_typeof(value -> 'quantity') = 'number' THEN
          (value ->> 'quantity')::numeric = trunc((value ->> 'quantity')::numeric)
          AND CASE WHEN value -> 'present' = 'true'::jsonb
            THEN (value ->> 'quantity')::numeric > 0
            ELSE (value ->> 'quantity')::numeric = 0
          END
        ELSE FALSE END
      ) IS TRUE
    SQL
  end
end
