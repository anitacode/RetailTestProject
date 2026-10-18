require "test_helper"
require "stringio"

class TrackingEvents::ImportProgressTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  test "shows progress and counts but reserves completion for success" do
    output = StringIO.new
    progress = TrackingEvents::ImportProgress.new(total: 1000, output: output)
    progress.update(processed: 500, inserted: 450)
    assert_includes output.string, "50% | 500/1,000 rows | staged: 450 | skipped: 50"

    progress.update(processed: 1000, inserted: 900)
    refute_includes output.string, "100%"
    progress.finish(processed: 1000, inserted: 900)
    assert_includes output.string, "100% | 1,000/1,000 rows | inserted: 900 | skipped: 100"
    refute_includes output.string, "\r"
  end

  test "failure reports rollback without claiming completion" do
    output = StringIO.new
    progress = TrackingEvents::ImportProgress.new(total: 501, output: output)
    progress.update(processed: 500, inserted: 500)
    progress.fail

    assert_includes output.string, "rolled back"
    refute_includes output.string, "100%"
    refute_includes output.string, "inserted:"
  end

  test "empty files can finish without dividing by zero" do
    output = StringIO.new
    progress = TrackingEvents::ImportProgress.new(total: 0, output: output)
    progress.finish(processed: 0, inserted: 0)

    assert_includes output.string, "100% | 0/0 rows | inserted: 0 | skipped: 0"
  end

  test "interactive output updates the same line and ends with a newline" do
    output = StringIO.new
    def output.tty? = true
    def output.winsize = [24, 160]
    progress = TrackingEvents::ImportProgress.new(total: 500, output: output)
    progress.update(processed: 500, inserted: 500)
    progress.finish(processed: 500, inserted: 500)

    assert_equal 3, output.string.count("\r")
    assert_equal 1, output.string.count("\n")
    assert output.string.end_with?("\n")
    visible_output = output.string.gsub(/\e\[[0-9;]*[mK]/, "")
    refute_includes visible_output, "["
    refute_includes visible_output, "]"
    assert_includes output.string, "\e[44m#{' ' * TrackingEvents::ImportProgress::WIDTH}\e[0m"
  end

  test "large counts stay on one line at different terminal widths" do
    [160, 100, 80, 40, 20].each do |columns|
      output = StringIO.new
      output.define_singleton_method(:tty?) { true }
      output.define_singleton_method(:winsize) { [24, columns] }
      progress = TrackingEvents::ImportProgress.new(total: 1_000_000, output: output, clock: -> { 0.0 })
      progress.update(processed: 500_000, inserted: 490_000)
      progress.finish(processed: 1_000_000, inserted: 990_000)

      frames = output.string.split("\r").reject(&:empty?)
      assert_equal 3, frames.length
      frames.each do |frame|
        assert frame.start_with?("\e[2K"), "Must clear previous frame"
        visible = frame.gsub(/\e\[[0-9;]*[mK]/, "").delete("\n")
        assert_operator visible.length, :<, columns, "Progress wraps at #{columns} columns"
      end
      assert_includes output.string, "100%"
    end
  end

  test "elapsed seconds include earlier counting time and update through completion" do
    output = StringIO.new
    now = 110.0
    progress = TrackingEvents::ImportProgress.new(total: 1000, output: output, started_at: 100.0, clock: -> { now })
    assert_includes output.string, "elapsed: 10.0s"

    now = 112.4
    progress.update(processed: 500, inserted: 500)
    assert_includes output.string.lines.last, "elapsed: 12.4s"

    now = 115.7
    progress.finish(processed: 1000, inserted: 1000)
    assert_includes output.string.lines.last, "100%"
    assert_includes output.string.lines.last, "elapsed: 15.7s"
  end
end
