module RailsQuery
  class Query
    DEFAULT_PAGE_SIZE = 20

    class << self
      attr_reader :fields, :links, :methods, :filters

      def inherited(child)
        child.instance_variable_set(:@fields, {})
        child.instance_variable_set(:@links, {})
        child.instance_variable_set(:@methods, {})
        child.instance_variable_set(:@filters, {})
      end
    end

    def self.model(model=nil)
      return @model unless model

      @model = model

      # add default id field and filter
      fields['id'] = Field.new('id', default: true, table: @model.table_name)
      filters['id'] = Filter.new('id', type: :equal, field: fields['id'])

      @model
    end

    def self.field(name, options={})
      options[:table] ||= model.table_name unless options[:join]

      count = options.delete(:count)
      field = Field.new(name, options)
      @fields[field.name] = field

      if options[:filter]
        filter(field.name, options.is_a?(Proc) ? options : {type: options[:filter]})
      end

      if count
        count_field = Field.new(count, options.merge(count: true))
        @fields[count_field.name] = count_field
      end

      self
    end

    def self.filter(name, options)
      name = name.to_s

      if options.is_a?(Hash)
        field_name = options[:field]&.to_s || name
        options[:field] = fields[field_name]
      end

      @filters[name] = Filter.new(name, options)
    end

    def self.link_one(name, options)
      link(name, options.merge(type: :one))
    end

    def self.link_many(name, options)
      link(name, options.merge(type: :many))
    end

    def self.link(name, options={})
      key = options[:key].to_s

      @links[name.to_s] = {
        type: options[:type] || :many,
        query: options[:query],
        key: key,
        key_on_link: fields[key] ? false : true
      }
    end

    def self.method(name, method)
      @methods[name.to_s] = method
    end

    def initialize
      @query_fields = self.class.fields.values.select(&:default).map(&:name)
      @query_methods = []
      @query_filters = {}
      @query_includes = {}
      @query_offset = nil
      @query_limit = nil
      @query_distinct = nil
    end

    def select(*names)
      names = names.flatten.map(&:to_s)
      @query_fields += names & self.class.fields.keys
      @query_methods += names & self.class.methods.keys if self.class.methods&.any?

      self
    end

    # eg: include([:model1, model2: [:field1, :field2]])
    def include(*select_links)
      select_links.each do |select_link|
        name, cols = select_link.is_a?(Hash) ? select_link.first : [select_link, []]
        name = name.to_s
        link = self.class.links[name]

        @query_includes[name] = cols.is_a?(Array) ? cols.map(&:to_s) : [cols.to_s]
        select(link[:key]) unless link[:key_on_link]
      end

      self
    end

    def filtrate(query)
      @query_filters = query

      self
    end

    def page(page)
      @query_page = page
      self
    end

    def limit(limit)
      @query_limit = limit
      self
    end

    def page_offset
      @query_page ? (@query_page - 1) * (@query_limit || DEFAULT_PAGE_SIZE) : 0
    end

    def order(order_hash)
      @query_order = order_hash
      self
    end

    def distinct(value=true)
      @query_distinct = value
      self
    end

    def group(value)
      @group = value
      self
    end

    def run
      add_links(
        add_methods(
          ActiveRecord::Base.connection.execute(sql).to_a
        )
      )
    end

    def meta
      return nil unless @query_page

      offset = (@query_page ? page_offset : @query_offset) || 0
      count = ar_query.count(:id) + offset

      {
        current_page: @query_page,
        total_pages: count / @query_limit,
        total_count: count,
        limit_value: @query_limit,
        offset_value: page_offset
      }
    end

    def ar_query
      q_cols = []
      q_joins = Set.new

      @query_fields.each do |field_name|
        if (field = self.class.fields[field_name])
          q_cols.push(field.select)
          q_joins.add(field.join) if field.join

          @query_group = self.class.fields['id'].path if field.count
        end
      end

      ar_query = self.class.model.select(q_cols).joins(q_joins.to_a)

      @query_filters.each do |key, val|
        if (filter = self.class.filters[key.to_s])
          ar_query = filter.apply(ar_query, val)
        end
      end

      ar_query = ar_query.distinct(@query_distinct) if @query_distinct
      ar_query = ar_query.group(@query_group) if @query_group
      ar_query = ar_query.order(@query_order) if @query_order
      ar_query = ar_query.offset(page_offset) if @query_page
      ar_query = ar_query.offset(@query_offset) if @query_offset
      ar_query = ar_query.limit(@query_limit) if @query_limit

      ar_query
    end

    def sql
      ar_query.to_sql
    end

    private

    def add_links(rows)
      return rows unless @query_includes

      @query_includes.each do |key, cols|
        next unless (link = self.class.links[key])

        cols.push(link[:key]) if link[:key_on_link]

        ids_key, link_key = if link[:key_on_link]
                              ['id', link[:key]]
                            else
                              [link[:key], 'id']
                            end

        ids = rows.map { |x| x[ids_key] }.uniq
        results = link[:query].new.select(cols).filtrate(link_key => ids).run

        rows = rows.map do |row|
          if link[:type] == :many
            row[key] = []

            results.each do |x|
              next if x[link_key] != row[ids_key]

              row[key].push(link[:key_on_link] ? x.except(link[:key]) : x)
            end
          else
            row[key] = results.find { |x| x['id'] == row[link[:key]] }
            row.delete link[:key]
          end

          row
        end
      end

      rows
    end

    def add_methods(rows)
      return rows unless self.class.methods && @query_methods.any?

      rows.map do |row|
        @query_methods.each do |name|
          row[name] = self.class.methods[name].call(row)
        end

        row
      end
    end
  end
end
