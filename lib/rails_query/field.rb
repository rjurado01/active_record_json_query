module RailsQuery
  class Field
    attr_reader :name, # field name
                :table, # table name
                :column, # table column
                :select, # sql select sentence to obtain field
                :join, # ActiveRecord::QueryMethods.joins arguments
                :default # field is returned always

    def initialize(name, options)
      @name = name.to_s
      @table = options[:table]
      @column = options[:column]
      @default = name == 'id' ? true : options[:default]

      if (@join = options[:join])
        initialize_join_field(options)
      elsif options[:select]
        @select = "#{ActiveRecord::Base.sanitize_sql(options[:select])} as #{name}"
      else
        @column ||= name
        @select = column == name ? name : "#{path} as #{name}"
      end
    end

    def path
      "#{@table}.#{@column}"
    end

    private

    def initialize_join_field(options)
      relation = join_relation(options[:join])

      @table ||= relation.pluralize
      @column ||= @name.remove("#{relation}_")
      @select = "#{path} as #{name}"
    end

    # returns join last table
    # - :a => 'a'
    # - {a: :b} => 'b'
    # - {a: {b: 'c'}} => 'c'
    def join_relation(join)
      case join
      when Hash then join.to_s.match(/(\w+)"?}/)[1]
      when String then join
      when Symbol then join.to_s
      else raise StandardError.new "Join :#{join} not valid"
      end
    end
  end
end
