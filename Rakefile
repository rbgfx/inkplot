# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:lint) { |task| task.options = ["--cache", "false"] }

task :types do
  sh "bundle exec rbs validate"
end

task verify: %i[lint spec types]
task default: :verify
