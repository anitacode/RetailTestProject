module TrackingEvents
  class ConsoleWatcher
    def initialize(store_id:, product_id:, output: $stdout)
      @pair = { store_id: store_id, product_id: product_id }
      @output = output
      @previous = {}
    end

    # Compare current observations, not insertion IDs: late imports must not
    # replace newer observations, and separate transactions can commit out of order.
    def poll
      TrackingEvent.uncached do
        {
          inventory: TrackingEvent.latest_inventory(**@pair),
          price: TrackingEvent.latest_price(**@pair)
        }.each do |category, event|
          value = observation_value(category, event)
          label = category == :price ? "Current price" : "Inventory"
          current = format_value(value)
          current = PASTEL.bold.green(current) if category == :price
          if !@previous.key?(category)
            @output.puts "#{label}: #{current} (initial)"
          elsif @previous[category] != value
            @output.puts "#{label}: #{format_value(@previous[category])} -> #{current}"
          end
          @previous[category] = value
        end
      end
      @output.flush
    end

    private

    def observation_value(category, event)
      return nil unless event

      if category == :inventory
        quantity = event.value.fetch("quantity").to_i
        event.in_stock? ? "in stock (#{quantity})" : "out of stock (#{quantity})"
      else
        [event.value.fetch("amount"), event.value.fetch("currency")]
      end
    end

    def format_value(value)
      return "unknown" if value.nil?
      return PASTEL.bright_white.on_red(value) if value.is_a?(String) && value.start_with?("out of stock (")
      return PASTEL.bright_white.on_green(value) if value.is_a?(String) && value.start_with?("in stock (")

      value.is_a?(Array) ? value.join(" ") : value
    end
  end
end
