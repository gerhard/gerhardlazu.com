require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:core) do |spec|
  spec.pattern     = Dir['spec/**/*_spec.rb']
  spec.rspec_opts  = %w(-fs --color)
end
