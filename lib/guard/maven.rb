require 'guard'
require 'guard/compat/plugin'

module Guard
  class Maven < Plugin

    # Initializes a Guard plugin.
    # Don't do any work here, especially as Guard plugins get initialized even
    # if they are not in an active group!
    #
    # @param [Array<Guard::Watcher>] watchers the Guard plugin file watchers
    # @param [Hash] options the custom Guard plugin options
    # @option options [Symbol] group the group this Guard plugin belongs to
    # @option options [Boolean] any_return allow any object to be returned from a watcher
    #
    def initialize(options = {})
      super
      @options = options
    end

    # Called once when Guard starts. Please override initialize method to init
    # stuff.
    #
    # @raise [:task_has_failed] when start has failed
    # @return [Object] the task result
    #
    def start
      run_all if @options[:all_on_start]
    end

    # Called when just `enter` is pressed
    # This method should be principally used for long action like running all
    # specs/tests/...
    #
    # @raise [:task_has_failed] when run_all has failed
    # @return [Object] the task result
    #
    def run_all
      run_maven
    end

    # Default behaviour on file(s) changes that the Guard plugin watches.
    # @param [Array<String>] paths the changes files or paths
    # @raise [:task_has_failed] when run_on_change has failed
    # @return [Object] the task result
    #
    def run_on_modifications(paths)
      if paths.include? 'all'
        run_all
      elsif paths.include? 'compile'
        run_maven :compile => true
      else
        run_maven :classes => paths
      end
    end

    private

    def notify(success, name, data={})
      title = 'Maven Tests'
      message = "Maven Test Results:"
      if data[:test_counts].empty?
        message += "No Tests Run"
      else
        message = guard_message(data[:test_counts][:total],
                                data[:test_counts][:fail],
                                data[:test_counts][:error],
                                data[:test_counts][:skip],
                                data[:total_time])
      end
      image = success ? :success : :failed
      Notifier.notify(message, title: title, image: image)
    end

    # Parses the results of the test run and
    # returns useful information for reporting:
    #  - number of tests
    #  - number of failed tests
    #  - number of errors
    #  - number of skipped tests
    #  - total time
    #
    # @param  results [String] The output of the test run
    #
    # @return [Hash] the relevant information
    def parse_test_results(results)
      data = { :success => true, :test_counts => [], :failures => [] }

      time = results.match(/\[INFO\] Total time: ([sm\d\.]+)/i)
      data[:total_time] = time[1] if time

      counts = results.match(/Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+)\n/)
      if counts
        data[:results] = counts[0]
        data[:test_counts] = {
          :total => counts[1].to_i,
          :fail => counts[2].to_i,
          :error => counts[3].to_i,
          :skip => counts[4].to_i,
          :pass => counts.to_a[1..-1].inject{|sum,x| sum.to_i - x.to_i }
        }

        data[:success] = false if counts[3].to_i + counts[2].to_i > 0
      end

      failures = results.match(/Failed tests:(.*)\n\nTests run/im)
      data[:failures] = failures ? failures[1].split("\n").compact : []

      if results =~ /COMPILATION ERROR/
        data[:success] = false
        data[:dump] = true
      end

      data
    end

    def run_maven(options={})
      puts # start with a newline to get past prompt.

      cmds = ['mvn']

      if options[:compile]
        cmds << 'compile'
        puts 'Compiling...'
      else
        cmds += ['test', '-DfailIfNoTests=false']
        if options[:classes]
          cmds << "-Dtest=#{options[:classes].join(',')}"
          options[:name] ||= options[:classes].join("\n")
          puts "Preparing tests for #{options[:classes].join(', ')}..."
        else
          puts "Preparing all tests..."
        end
      end

      cmds << @options[:args] if @options[:args]
      cmd = cmds.join ' '
      puts cmd

      # Use popen so that we can capture the test output as well as display it
      # in terminal
      output = []
      str = []
      IO.popen(cmd).each_char do |char|
        char.encode!('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
        print char if @options[:verbose]

        if char == "\n"
          line = str.join.chomp
          str = []
          clean_output line unless @options[:verbose]
          output << line
        else
          str << char
        end
      end.close
      results = output.join("\n")

      # Did the system command return successfully?
      success = $?.success?

      data = parse_test_results(results)
      success = false unless data[:success]

      unless @options[:verbose]
        puts "Failed Tests:\n#{data[:failures].join("\n")}" unless data[:failures].empty?
        puts results if data[:dump]
      end

      notify(success, options[:name] || '', data)
    end

    def clean_output(line)
      if line =~ /^Running/
        puts line
      elsif output = line.match(/Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+), Time elapsed:/)
        match, total, fail, error, skip = output.to_a
        pass = total.to_i - fail.to_i - error.to_i - skip.to_i
        print "." * pass
        print "E" * error.to_i
        print "F" * fail.to_i
        print "S" * skip.to_i
        puts ""
      else
        # do nothing
      end
    end

    def guard_message(test_count, failure_count, error_count, skip_count, duration)
      message = "#{test_count} tests"
      if skip_count > 0
        message << " (#{skip_count} skipped)"
      end
      message << "\n#{failure_count} failures, #{error_count} errors"
      if test_count
        message << "\n\nFinished in #{duration}"
      end
      message
    end
  end
end
