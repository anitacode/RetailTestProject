class AddSeenAtToAlerts < ActiveRecord::Migration[7.1]
  def change
    add_column :alerts, :seen_at, :datetime
  end
end
