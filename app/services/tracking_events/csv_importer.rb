require "csv"

module TrackingEvents
  class CsvImporter
    BATCH_SIZE = 1_500

    class InvalidRow < StandardError
      attr_reader :record_number

      def initialize(record_number, reason)
        @record_number = record_number
        super("CSV record #{record_number}: #{reason}")
      end
    end

    def initialize(path)
      @path = path
    end

    def call
      row_count = 0
      created_count = 0

      TrackingEvent.transaction(requires_new: true) do
        CSV.foreach(@path, headers: true).each_slice(BATCH_SIZE) do |rows|
          store_ids = ids_by(Store, :address, rows.map { |row| row["Address"] })
          product_matches = products_by_name(rows.map { |row| row["Product Name"] })

          events = []
          rows.each_with_index do |row, index|
            # Count CSV records including the header, not physical lines: quoted
            # fields may contain newlines.
            record_number = row_count + index + 2
            store_id = store_ids[row["Address"]]
            product_id, match_count = product_matches[row["Product Name"]]
            raise InvalidRow.new(record_number, "store not found for Address #{row['Address'].inspect}") unless store_id
            raise InvalidRow.new(record_number, "product not found for Product Name #{row['Product Name'].inspect}") unless product_id
            if match_count > 1
              raise InvalidRow.new(record_number,
                                   "Product Name #{row['Product Name'].inspect} matches #{match_count} products; cannot choose a product without a unique identifier")
            end

            quantity = parse_quantity(row, record_number)
            event_time = parse_date(row["Date"], record_number)
            inventory_present = quantity > 0

            events << {
              event_type: "inventory_presence",
              store_id:,
              product_id:,
              event_time:,
              inventory_present:,
              value: { quantity: quantity }
            }
          end

          if events.any?
            TrackingEvent.insert_all!(events, record_timestamps: true, returning: false)
          end
          created_count += events.length
          row_count += rows.length

          yield(processed: row_count, inserted: created_count) if block_given?
        end
        # Bulk writes bypass callbacks. Queue one reconciliation in the same
        # database transaction; workers cannot see it until the import commits.
        Alerts::ReconcileJob.perform_later if created_count.positive?
      end

      Rails.logger.info "[TrackingEvents::CsvImporter] rows processed=#{row_count} created=#{created_count}"
      { processed: row_count, inserted: created_count }
    end

    private

    def products_by_name(names)
      # Aggregate in PostgreSQL to keep one lookup per batch and avoid loading
      # every matching product. The ID is used only when the count is one.
      Product.where(name: names.uniq).group(:name)
             .pluck(:name, Arel.sql("MIN(id)"), Arel.sql("COUNT(*)"))
             .to_h { |name, id, count| [name, [id, count]] }
    end

    def parse_quantity(row, record_number)
      row.headers.include?("Quantity") ? Integer(row["Quantity"], 10) : (cast_boolean(row["Inventory Present"]) ? 1 : 0)
    rescue ArgumentError, TypeError
      raise InvalidRow.new(record_number, "Quantity must be a whole number; got #{row['Quantity'].inspect}")
    end

    def parse_date(value, record_number)
      Date.parse(value)
    rescue ArgumentError, TypeError
      raise InvalidRow.new(record_number, "invalid Date #{value.inspect}")
    end

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
