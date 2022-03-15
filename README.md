# RailsQuery

Layer above ActiveRecord to define your models query interface.

### Features

Extract your query logic from models to a query class using:

* Fields
* Filters
* Orders
* Pagination

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_query'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install rails_query

## Usage

```ruby
class UserQuery < RailsQuery::Query
  init User

  ## FIELDS

  field :name
  field :lastname
  field :age

  field :fullname do |query|
    query.select("name || ' ' || lastname as fullname")
  end

  field :country_name do |query|
    query.joins(region: :country).select('countries.name')
  end

  field(
    :region, # includes object
    as_json: {include: {region: {only: %i[id name]}}}
  ) do |query|
    query.select(:region_id).includes(:region)
  end

  ## FILTERS

  filter :under_age do |query, _val|
    query.where(age: 1..17)
  end

  filter :country_name do |query, val|
    query.joins(region: :country).where(countries: {name: val})
  end

  filter :lastname, operator: :contain
  filter :age_gt, operator: :gt, column: :age
  filter :age_lt, operator: :lt, column: :age
  filter :age_range, operator: :range, column: :age

  ## ORDER

  order :name

  order :country_name do |query, dir|
    query.joins(region: :country).order('countries.name' => dir)
  end
end

query = UserQuery.new({
  fields: %i[name, country_name, region],
  filters: {under_age: true, age_gt: 18},
  order: {country_name: 'asc', name: 'desc'},
  page: {number: 2, size: 1}
})

result = {data: query.run, meta: query.meta}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/rails_query. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/rails_query/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RailsQuery project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/rails_query/blob/master/CODE_OF_CONDUCT.md).
