module M
  ### Runner is in charge of running your tests.
  # Instead of slamming all of this junk in an `M` class, it's here instead.
  class Runner
    def initialize(argv)
      @argv = argv
    end

    def run
      parse
      execute
    end

    private

    def parse
      # With no arguments,
      if @argv.empty?
        # Just shell out to `rake test`.
        exec "rake test"
      else
        # Parse out ARGV, it should be coming in in a format like `test/test_file.rb:9`
        @file, line = @argv.first.split(':')
        @line = line.to_i

        # If this file is a directory, not a file, run the tests inside of this directory
        if Dir.exist?(@file)
          # Make a new rake task with a hopefully unique name, and run every test looking file in it
          Rake::TestTask.new(:m_custom) do |t|
            t.libs << 'test'
            t.pattern = "#{@file}/*test*.rb"
          end
          # Invoke the rake task and exit, hopefully it'll work!
          Rake::Task['m_custom'].invoke
          exit
        end
      end
    end

    def execute
      # Locate tests to run that may be inside of this line. There could be more than one!
      tests_to_run = tests.within(@line)

      # If we found any tests,
      if tests_to_run.size > 0
        # assemble the regexp to run these tests,
        test_names = tests_to_run.map(&:name).join('|')

        # directly run the tests from here and exit with the status of the tests passing or failing
        exit Test::Unit::AutoRunner.run(false, nil, ["-n", "/(#{test_names})/"])
      else
        # Otherwise we found no tests on this line, so you need to pick one.
        message = "No tests found on line #{@line}. Valid tests to run:\n\n"

        # For every test ordered by line number,
        # spit out the test name and line number where it starts,
        tests.by_line_number do |test|
          message << "#{sprintf("%0#{tests.column_size}s", test.name)}: m #{@file}:#{test.start_line}\n"
        end

        # fail like a good unix process should.
        abort message
      end
    end

    # Finds all test suites in this test file, with test methods included.
    def suites
      # Since we're not using `ruby -Itest` to run the tests, we need to add this directory to the `LOAD_PATH`
      $:.unshift "./test"

      begin
        # Fire up this Ruby file. Let's hope it actually has tests.
        load @file
      rescue LoadError => e
        # Fail with a happier error message instead of spitting out a backtrace from this gem
        abort "Failed loading test file:\n#{e.message}"
      end

      # Use some janky internal test/unit API to group test methods by test suite.
      Test::Unit::TestCase.test_suites.inject({}) do |suites, suite_class|
        # End up with a hash of suite class name to an array of test methods, so we can later find them and ignore empty test suites
        suites[suite_class] = suite_class.test_methods if suite_class.test_methods.size > 0
        suites
      end
    end

    # Shoves tests together in our custom container and collection classes.
    # Memoize it since it's unnecessary to do this more than one for a given file.
    def tests
      @tests ||= begin
        # With each suite and array of tests,
        # and with each test method present in this test file,
        # shove a new test method into this collection.
        suites.inject(TestCollection.new) do |collection, (suite_class, test_methods)|
          test_methods.each do |test_method|
            collection << TestMethod.create(suite_class, test_method)
          end
          collection
        end
      end
    end
  end
end
