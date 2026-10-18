require "io/console"

module TrackingEvents
  class ImportProgress
    WIDTH = 20
    PARTIAL_BLOCKS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"].freeze
    FRAMES = %w[| / - \\].freeze

    def initialize(total:, output: $stdout, started_at: nil, message: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @total = total
      @output = output
      @interactive = output.tty?
      @last_percent = nil
      @clock = clock
      @started_at = started_at || @clock.call
      @message = message
      @mutex = Mutex.new
      @frame = 0
      @header_drawn = false
      total.nil? ? render(0, message) : update(processed: 0, inserted: 0)
    end

    # Keep the terminal moving even while counting or waiting on the database.
    def with_animation
      return yield unless @interactive

      worker = Thread.new do
        loop do
          sleep 0.1
          @mutex.synchronize do
            @frame += 1
            draw(*@last_render)
          end
        end
      end
      yield
    ensure
      if worker
        worker.kill
        worker.join
      end
    end

    def end_line
      @output.puts if @interactive
      @output.flush
    end

    def finish_counting
      render(100, @message) if @interactive
    end

    def update(processed:, inserted:)
      # Reserve 100% for successful completion of the transaction.
      percent = @total.zero? ? 0 : [(processed * 100 / @total), 99].min
      return if !@interactive && percent == @last_percent

      render(percent, "#{format_count(processed)}/#{format_count(@total)} rows | staged: #{format_count(inserted)} | skipped: #{format_count(processed - inserted)}")
    end

    def finish(processed:, inserted:)
      render(100, "#{format_count(processed)}/#{format_count(@total)} rows | inserted: #{format_count(inserted)} | skipped: #{format_count(processed - inserted)}")
      @output.puts if @interactive
    end

    def fail
      @output.puts if @interactive
      @output.puts "Import failed; changes from this import were rolled back."
      @output.flush
    end

    private

    def format_count(value)
      value.to_s.reverse.scan(/.{1,3}/).join(",").reverse
    end

    def render(percent, details)
      @mutex.synchronize do
        @last_render = [percent, details]
        draw(percent, details)
      end
    end

    def draw(percent, details)
      if @total.nil?
        line = @message.to_s
        if @interactive
          line = status_header(line, percent)
          @output.print "\r\e[2K#{line}"
        else
          @output.puts line
        end
        @output.flush
        return
      end

      elapsed = format("%.1f", @clock.call - @started_at)
      if @message
        if @interactive
          @output.print "\e[2A" if @header_drawn
          header = status_header(@message, percent)
          @output.print "\r\e[2K#{header}\n\r\e[2K\n"
        elsif !@header_drawn
          @output.puts @message
          @output.puts
        end
        @header_drawn = true
      end
      suffix = " #{percent.to_s.rjust(3)}% | #{details} | elapsed: #{elapsed}s"
      suffix = " #{FRAMES[@frame % FRAMES.length]}#{suffix}" if @interactive && !@message && percent < 100
      width = WIDTH
      if @interactive
        # Leave the last column unused to avoid terminal auto-wrap.
        available = [terminal_columns - 1, 0].max
        if suffix.length + WIDTH > available
          rows = details.split(" | ").first
          suffix = " #{percent}% | #{rows} | #{elapsed}s"
          suffix = " #{FRAMES[@frame % FRAMES.length]}#{suffix}" if !@message && percent < 100
        end
        if suffix.length + WIDTH > available
          suffix = " #{percent}% | #{elapsed}s"
          suffix = " #{FRAMES[@frame % FRAMES.length]}#{suffix}" if !@message && percent < 100
        end
        suffix = suffix[0, available]
        width = [WIDTH, available - suffix.length].min
      end

      filled = percent * width / 100
      bar = if @interactive
        # Eighth-width blocks make each 1% increment visible at the normal width.
        units = percent * width * 8 / 100
        full, fraction = units.divmod(8)
        partial = PARTIAL_BLOCKS[fraction]
        empty = width - full - (fraction.zero? ? 0 : 1)
        "\e[44m#{' ' * full}\e[0m\e[34m#{partial}\e[0m#{' ' * empty}"
      else
        "#{'=' * filled}#{' ' * (width - filled)}"
      end
      line = "#{bar}#{suffix}"
      if @interactive
        @output.print "\r\e[2K#{line}"
      else
        @output.puts line
      end
      @output.flush
      @last_percent = percent
    end

    def status_header(message, percent)
      indicator = percent < 100 ? FRAMES[@frame % FRAMES.length] : " ✓ "
      line = "#{indicator} #{message}"[0, [terminal_columns - 1, 0].max]
      # Apply color after truncation so terminal escape sequences stay intact.
      percent < 100 ? line : line.sub(/\A ✓ /, "\e[1;97;42m ✓ \e[0m")
    end

    def terminal_columns
      columns = @output.winsize.last if @output.respond_to?(:winsize)
      columns = ENV.fetch("COLUMNS", "80").to_i unless columns&.positive?
      columns.positive? ? columns : 80
    rescue IOError, SystemCallError
      80
    end
  end
end
