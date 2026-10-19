require "test_helper"
require "minitest/mock"
require "rake"
require "tmpdir"
require "csv"

class TrackingEventsImportTaskTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  test "invalid row reports its location and exits unsuccessfully without a done message" do
    original_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/tracking_events_import.rake")

    Dir.mktmpdir("import-task-test") do |directory|
      File.write(File.join(directory, "tracking_events.csv"), CSV.generate do |csv|
        csv << ["Address", "Product Name", "Date", "Inventory Present"]
        csv << ["Nonexistent test store", "Nonexistent test product", "2026-10-19", "True"]
      end)
      stdout, stderr = capture_io do
        Rails.stub(:root, Pathname.new(directory)) do
          failure = assert_raises(SystemExit) { Rake::Task["tracking_events:import"].invoke }
          assert_equal 1, failure.status
        end
      end
      assert_includes stdout, "rolled back"
      assert_includes stderr, "CSV record 2: store not found"
      refute_includes stdout, "Done"
      refute_includes stdout, "100%"
    end
  ensure
    Rake.application = original_application
  end
end
