# frozen_string_literal: true

require "./lib/dependabot"

Gem::Specification.new do |spec|
  spec.name         = "dependabot-common"
  spec.version      = Dependabot::VERSION
  spec.summary      = "Shared code used between Dependabot package managers"
  spec.description  = "Automated dependency management for Ruby, JavaScript, " \
                      "Python, PHP, Elixir, Rust, Java, .NET, Elm and Go"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/dependabot/dependabot-core"
  spec.license      = "Nonstandard" # License Zero Prosperity Public License

  spec.require_path = "lib"
  spec.files        = []

  spec.required_ruby_version = ">= 3.1.0"
  spec.required_rubygems_version = ">= 3.3.7"

  spec.add_dependency "aws-sdk-codecommit", "~> 1.28"
  spec.add_dependency "aws-sdk-ecr", "~> 1.5"
  spec.add_dependency "bundler", ">= 1.16", "< 3.0.0"
  spec.add_dependency "commonmarker", ">= 0.20.1", "< 0.24.0"
  spec.add_dependency "docker_registry2", "~> 1.13"
  spec.add_dependency "excon", "~> 0.96", "< 0.100"
  spec.add_dependency "faraday", "2.7.4"
  spec.add_dependency "faraday-retry", "2.0.0"
  spec.add_dependency "gitlab", "4.19.0"
  spec.add_dependency "nokogiri", "~> 1.8"
  spec.add_dependency "octokit", ">= 4.6", "< 7.0"
  spec.add_dependency "parser", ">= 2.5", "< 4.0"
  spec.add_dependency "toml-rb", ">= 1.1.2", "< 3.0"

  spec.add_development_dependency "debug", "~> 1.7.1"
  spec.add_development_dependency "gpgme", "~> 2.0"
  spec.add_development_dependency "parallel_tests", "~> 4.2.0"
  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-its", "~> 1.3"
  spec.add_development_dependency "rubocop", "~> 1.48.0"
  spec.add_development_dependency "rubocop-performance", "~> 1.16.0"
  spec.add_development_dependency "simplecov", "~> 0.22.0"
  spec.add_development_dependency "simplecov-console", "~> 0.9.1"
  spec.add_development_dependency "stackprof", "~> 0.2.16"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "webmock", "~> 3.18"

  next unless File.exist?("../.gitignore")

  spec.files += `git -C #{__dir__} ls-files lib bin -z`.split("\x0")
end
