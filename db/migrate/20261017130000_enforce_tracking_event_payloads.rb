class EnforceTrackingEventPayloads < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :tracking_events, name: "tracking_events_value_structure"
    change_column_default :tracking_events, :value, from: { "type" => "null", "value" => nil }, to: nil

    # Preserve both true and false from the original typed payloads.
    execute <<~SQL
      UPDATE tracking_events
      SET value = jsonb_build_object('present', value -> 'value')
      WHERE event_type = 'inventory_presence'
        AND value ->> 'type' = 'boolean'
        AND jsonb_typeof(value -> 'value') = 'boolean'
        AND NOT (value ? 'present')
    SQL

    add_check_constraint :tracking_events, "jsonb_typeof(value) = 'object'",
      name: "tracking_events_value_structure"
    # IS TRUE rejects missing keys as well as JSON null (CHECK otherwise accepts SQL NULL).
    add_check_constraint :tracking_events, <<~SQL.squish, name: "tracking_events_inventory_payload"
      event_type <> 'inventory_presence' OR
      (jsonb_typeof(value -> 'present') = 'boolean') IS TRUE
    SQL
    # CASE guards the numeric cast so malformed JSON yields a constraint violation.
    add_check_constraint :tracking_events, <<~SQL.squish, name: "tracking_events_price_payload"
      event_type <> 'price_tracker' OR (
        CASE WHEN jsonb_typeof(value -> 'amount') = 'number'
          THEN (value ->> 'amount')::numeric >= 0
          ELSE FALSE
        END
        AND jsonb_typeof(value -> 'currency') = 'string'
        AND char_length(value ->> 'currency') = 3
        AND (value ->> 'currency') ~ '^[A-Z]{3}$'
      ) IS TRUE
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Payloads have been converted to event-specific objects"
  end
end
