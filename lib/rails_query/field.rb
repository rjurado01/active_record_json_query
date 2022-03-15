module RailsQuery
  class Field
    attr_reader :name, # field name
                :as_json,
                :block

    def initialize(name, options, block)
      @name = name.to_s
      @as_json = options[:as_json]
      @block = block || ->(query) { query.select(name) }
    end
  end
end
