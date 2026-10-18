require "csv"

module TrackingEvents
  class CsvImporter
    BATCH_SIZE = 1_500

    def initialize(path)
      @path = path
    end

    def call
      row_count = 0
      created_count = 0

      TrackingEvent.transaction(requires_new: true) do
        CSV.foreach(@path, headers: true).each_slice(BATCH_SIZE) do |rows|
          row_count += rows.length
          store_ids = ids_by(Store, :address, rows.map { |row| row["Address"] })
          product_ids = ids_by(Product, :name, rows.map { |row| row["Product Name"] })

          events = []
          rows.each do |row|
            store_id = store_ids[row["Address"]]
            product_id = product_ids[row["Product Name"]]
            break if !store_id || !product_id

            inventory_present = cast_boolean(row["Inventory Present"])

            events << {
              event_type: "inventory_presence",
              store_id:,
              product_id:,
              event_time: Date.parse(row["Date"]),
              inventory_present:,
              value: { present: inventory_present }
            }
          end

          if events.any?
            TrackingEvent.insert_all!(events, record_timestamps: true, returning: false)
          end
          created_count += events.length

          yield(processed: row_count, inserted: created_count) if block_given?
        end
      end

      Rails.logger.info "[TrackingEvents::CsvImporter] rows processed=#{row_count} created=#{created_count}"
      { processed: row_count, inserted: created_count }
    end

    private

    def ids_by(model, column, values)
      # For demo purposes :)
      # Validate argument types explicitly because Ruby does not enforce them.
      # model: an ActiveRecord::Base subclass
      # column: a Symbol or String identifying the lookup column
      # values: an Array of values to look up in that column
      unless model.is_a?(Class) && model < ActiveRecord::Base
        raise TypeError, "model must be an ActiveRecord::Base subclass"
      end
      unless column.is_a?(Symbol) || column.is_a?(String)
        raise TypeError, "column must be a Symbol or String"
      end
      raise TypeError, "values must be an Array" unless values.is_a?(Array)

      model.where(column => values.uniq).order(:id).pluck(column, :id).each_with_object({}) do |(value, id), ids|
        ids[value] ||= id
      end
    end

    def cast_boolean(value)
      case value
      when true, "true", "TRUE", "t", "T", "1", "True" then true
      else false
      end
    end
  end
end
