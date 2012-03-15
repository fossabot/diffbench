require "yaml"
require "benchmark"
require "git"

class DiffBench

  class Runner
    def initialize(file, *args)
      @file = file
      unless @file
        raise Error, "File not specified"
      end
    end

    def run
      puts "Running benchmark with current working tree"
      first_run = run_file
      if tree_dirty?
        puts "Stashing changes"
        git_run "stash"
        puts "Running benchmark with clean working tree"
        begin
          second_run = run_file
        ensure
          puts "Applying stashed changes back"
          git_run "stash pop"
        end
      elsif branch = current_head
        puts "Checkout HEAD^"
        git_run "checkout 'HEAD^'"
        puts "Running benchmark with HEAD^"
        begin
          second_run = run_file
        ensure
          puts "Checkout to previous HEAD again"
          git_run "checkout #{branch}"
        end
      else
        raise Error, "No current branch."
      end
      puts ""
      caption = "Before patch: ".gsub(/./, " ") +  Benchmark::Tms::CAPTION
      puts caption
      first_run.keys.each do |test|
        puts ("-"* (caption.size - test.size)) + test
        puts "After patch:  #{first_run[test].format}"
        puts "Before patch: #{second_run[test].format}"
        puts ""
      end
    end

    def current_head
      branch = git.current_branch.to_s 
      return branch if !(branch == "(no branch)")
      branch = git_run("symbolic-ref HEAD").gsub(/^refs\/head\//, "")
      return branch unless branch.empty?
    rescue Git::GitExecuteError
      branch = git_run("rev-parse HEAD")[0..7]
      return branch
    end

    def run_file
      output = `ruby #{@file}`
      begin
        result = YAML.load(output) 
        raise Error, "Can not parse result of ruby script: \n #{output}" unless result.is_a?(Hash)
        result
      rescue Psych::SyntaxError
        raise Error, "Can not run ruby script: \n#{output}"
      end
    end

    def git_run(command)
      git.lib.send(:command, command)
    end

    def git
      @git ||= Git.open(discover_git_dir)
    end

    def discover_git_dir
      tokens = ENV['PWD'].split("/")
      while tokens.any?
        path = tokens.join("/")
        if File.exists?(path + "/.git")
          return path
        end
        tokens.pop
      end
      raise Error, "Git working dir not found"
    end

    def tree_dirty?
      status = git.status
      status.deleted.any? || status.changed.any? || status.added.any?
    end
  end

  class << self

    def run(*args)
      Runner.new(*args).run
    end
    def bm(&block)
      DiffBench::Bm.new(&block)
    end

  end

  class Bm
    def initialize(&block)
      @measures = {}
      if block.arity == -1 || block.arity > 0
        block.call(self)
      else
        instance_eval(&block)
      end

      puts @measures.to_yaml
    end


    def report(label)
      @measures[label] = Benchmark.measure do
        yield
      end
    end
  end
  class Error < StandardError; end
end
