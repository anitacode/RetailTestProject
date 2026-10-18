require "csv"

namespace :tracking_events do
  desc "Import tracking events from tracking_events.csv located in the app root"
  task import: :environment do
    path = Rails.root.join("tracking_events.csv")

    unless File.exist?(path)
      puts "ERROR: File not found:"
      puts "  #{path}"
      puts ""
      puts "Place tracking_events.csv in the top-level directory of the Rails app."
      exit 1
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    counting = TrackingEvents::ImportProgress.new(total: nil, message: "Counting CSV rows in #{path}...")
    # Count CSV records, not lines, so quoted multiline fields are handled correctly.
    begin
      total = counting.with_animation { CSV.foreach(path, headers: true).count }
      counting.finish_counting
    ensure
      counting.end_line
    end
    puts
    formatted_total = total.to_s.reverse.scan(/.{1,3}/).join(",").reverse
    progress = TrackingEvents::ImportProgress.new(
      total: total, started_at: started_at,
      message: "Importing #{formatted_total} tracking-event rows..."
    )

    begin
      result = progress.with_animation do
        TrackingEvents::CsvImporter.new(path).call do |counts|
          progress.update(**counts)
        end
      end
    rescue StandardError
      progress.fail
      raise
    end

    progress.finish(**result)
    puts
    puts($stdout.tty? ? "\e[1;97;42m Done :) \e[0m" : "Done.")
  end
end
