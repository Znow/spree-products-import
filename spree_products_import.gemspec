# encoding: UTF-8
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_products_import'
  s.version     = '3.4.4'
  s.summary     = 'Import products and variant data from csv files in a delayed job'
  s.description = 'Add an admin option for importing and updating product/variant data via csv files'
  s.required_ruby_version = '>= 2.0.0'

  s.author    = 'Nimish Mehta'
  s.email     = 'nimish@vinsol.com'
  # s.homepage  = 'http://www.spreecommerce.com'

  #s.files       = `git ls-files`.split("\n")
  #s.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree_core', '~> 3.6.2'
  s.add_dependency 'delayed_job_active_record'

  s.add_development_dependency 'capybara', '~> 2.4'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'coffee-rails'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'factory_girl', '~> 4.5'
  s.add_development_dependency 'ffaker'
  s.add_development_dependency 'rspec-rails',  '~> 3.1'
  s.add_development_dependency 'sass-rails', '~> 5.0.0.beta1'
  s.add_development_dependency 'selenium-webdriver'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'sqlite3'
end
