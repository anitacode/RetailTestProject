namespace :tracking_events do
  desc "Watch current inventory and price: STORE_ID=1 PRODUCT_ID=1 [INTERVAL=1]"
  task watch: :environment do
    store = Store.find(ENV.fetch("STORE_ID"))
    product = Product.find(ENV.fetch("PRODUCT_ID"))
    interval = Float(ENV.fetch("INTERVAL", "1"))
    abort "INTERVAL must be a finite positive number" unless interval.finite? && interval.positive?

    puts "Product: #{PASTEL.bold(product.name)} (#{product.id})"
    puts "Shop: #{PASTEL.bold(store.address)} (#{store.id})"
    puts "Checking every #{interval}s. Ctrl-C to stop."
    watcher = TrackingEvents::ConsoleWatcher.new(store_id: store.id, product_id: product.id)
    begin
      loop do
        watcher.poll
        sleep interval
      end
    rescue Interrupt
      puts "\nWatcher stopped."
    end
  end
end
