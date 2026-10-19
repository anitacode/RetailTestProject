class CreateSmsDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :sms_deliveries do |t|
      t.references :alert, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :phone_number, null: false
      t.text :body, null: false
      t.datetime :simulated_at, null: false
      t.timestamps
    end
  end
end
