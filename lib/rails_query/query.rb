module RailsQuery
  class Query
    DEFAULT_PAGE_SIZE = 20

    class << self
      attr_reader :model, :fields, :methods, :filters, :default_cols, :relations
    end

    def self.model(model=nil)
      model ? @model = model : @model
    end

    def self.field(name, options={})
      name = name.to_s

      if options[:join]
        relation = join_relation(options[:join])
        options[:table] ||= relation.pluralize
        options[:column] ||= name.remove("#{relation}_")
        options[:path] ||= "#{options[:table]}.#{options[:column]}"
        options[:select] = "#{options[:path]} as #{name}"
      elsif options[:select]
        options[:select] = "#{ActiveRecord::Base.sanitize_sql(options[:select])} as #{name}"
      else
        options[:column] ||= name
        options[:select] = options[:column] == name ? name : "#{options[:column]} as #{name}"
      end

      @fields ||= {'id' => {select: 'id'}}
      @fields[name.to_s] = options

      @default_cols ||= ['id']
      @default_cols.push(name.to_s) if options[:default]

      filter(name.to_s, options.delete(:filter)) if options[:filter]
    end

    def self.join_relation(join)
      (join.is_a?(Hash) ? join.values.last : join).to_s
    end

    def self.filter(name, filter)
      @filters ||= {}
      @filters[name.to_s] = filter
    end

    def self.relation(name, options)
      @relations ||= {}
      @relations[name.to_s] = {
        query: options[:query],
        through: options[:through].to_s
      }
    end

    def self.method(name, method)
      @methods ||= {}
      @methods[name.to_s] = method
    end

    def initialize
      @select_cols = self.class.default_cols
      @select_methods = []
      @includes = {}
      @offset = nil
      @limit = nil
      @query = {}
    end

    def select(*cols)
      cols = cols.flatten.map(&:to_s)
      @select_cols += cols & self.class.fields.keys
      @select_methods += cols & self.class.methods.keys if self.class.methods&.any?

      self
    end

    def include(*relations)
      relations.each do |relation|
        if relation.is_a?(Hash)
          key, cols = relation.first
          @includes[key.to_s] = cols.is_a?(Array) ? cols.map(&:to_s) : [cols.to_s]
        else
          @includes[relation.to_s] = []
        end
      end

      self
    end

    def filtrate(query)
      @query = query

      self
    end

    def page(page)
      @page = page
      self
    end

    def limit(limit)
      @limit = limit
      self
    end

    def page_offset
      @page ? (@page - 1) * (@limit || DEFAULT_PAGE_SIZE) : 0
    end

    def order(order_hash)
      @order = order_hash
      self
    end

    def run
      add_relations(
        add_methods(
          ActiveRecord::Base.connection.execute(sql).to_a
        )
      )
    end

    def meta
      return nil unless @page

      count = query.count(:id)

      {
        current_page: @page,
        total_pages: count / @limit,
        total_count: count,
        limit_value: @limit,
        offset_value: page_offset
      }
    end

    def query
      q_cols = []
      q_joins = Set.new

      @select_cols.each do |col|
        field = self.class.fields[col]

        q_cols.push(field[:select])
        q_joins.add(field[:join]) if field[:join]
      end

      query = self.class.model.select(q_cols).joins(q_joins.to_a).order(@order)

      @query.each do |key, val|
        filter = self.class.filters[key.to_s]

        next unless filter && filter.is_a?(Proc)

        query = query.instance_exec(val, &filter)
      end

      query
    end

    def sql
      query.offset(@offset || page_offset).limit(@limit).to_sql
    end

    def add_relations(rows)
      return rows unless @includes

      ids = rows.map { |x| x['id'] }

      @includes.each do |key, cols|
        next unless (relation = self.class.relations[key])

        cols.push(relation[:through])

        results = relation[:query].new.select(cols).filtrate(relation[:through] => ids).run

        rows = rows.map do |row|
          row[key] = []

          results.each do |x|
            row[key].push(x.except(relation[:through])) if x[relation[:through]] == row['id']
          end

          row
        end
      end

      rows
    end

    def add_methods(rows)
      return rows unless self.class.methods
      return rows unless (select_methods = @select_methods & self.class.methods.keys).any?

      rows.map do |row|
        select_methods.each do |name|
          row[name] = self.class.methods[name].call(row)
        end

        row
      end
    end
  end
end
