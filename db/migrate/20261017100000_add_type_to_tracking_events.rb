class AddTypeToTrackingEvents < ActiveRecord::Migration[7.1]
  def change
    create_enum :tracking_event_type, ["inventory_presence", "price_tracker"]
    add_column :tracking_events, :type, :enum,
               enum_type: :tracking_event_type, default: "inventory_presence", null: false
  end
end
