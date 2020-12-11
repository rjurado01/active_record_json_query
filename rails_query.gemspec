require_relative 'lib/rails_query/version'

Gem::Specification.new do |spec|
  spec.name          = "rails_query"
  spec.version       = RailsQuery::VERSION
  spec.authors       = ['rjurado01']
  spec.email         = ['rjurado01@gmail.com']

  spec.summary       = 'Easy way to build queries on Ruby On Rails.'
  spec.description   = 'Easy way to build queries with filters, order, pagination... on RoR.'
  spec.homepage      = 'https://github.com/rjurado01/rails_query.'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', ['>= 3.0', '< 6.1']
end
