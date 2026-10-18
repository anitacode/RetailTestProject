class RenameTypeToEventTypeInTrackingEvents < ActiveRecord::Migration[7.1]
  def change
    rename_column :tracking_events, :type, :event_type
  end
end
