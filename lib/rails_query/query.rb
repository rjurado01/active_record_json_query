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

      # add default id field
      fields['id'] = Field.new('id', default: true, table: @model.table_name)

      @model
    end

    def self.field(name, options={})
      options[:table] ||= model.table_name unless options[:join]

      field = Field.new(name, options)
      @fields[field.name] = field

      filter(field.name, options[:filter]) if options[:filter]
    end

    def self.filter(name, filter)
      @filters ||= {id: ->(val) { where(id: val) }}
      @filters[name.to_s] = filter
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
      @select_fields = self.class.fields.values.select(&:default).map(&:name)
      @select_methods = []
      @includes = {}
      @offset = nil
      @limit = nil
      @distinct = nil
      @query = {}
    end

    def select(*names)
      names = names.flatten.map(&:to_s)
      @select_fields += names & self.class.fields.keys
      @select_methods += names & self.class.methods.keys if self.class.methods&.any?

      self
    end

    # eg: include([:model1, model2: [:field1, :field2]])
    def include(*select_links)
      select_links.each do |select_link|
        name, cols = select_link.is_a?(Hash) ? select_link.first : [select_link, []]
        name = name.to_s
        link = self.class.links[name]

        @includes[name] = cols.is_a?(Array) ? cols.map(&:to_s) : [cols.to_s]
        select(link[:key]) unless link[:key_on_link]
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

    def distinct(value=true)
      @distinct = value
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
      return nil unless @page

      offset = (@page ? page_offset : @offset) || 0
      count = query.count(:id) + offset

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

      @select_fields.each do |field_name|
        field = self.class.fields[field_name]

        q_cols.push(field.select)
        q_joins.add(field.join) if field.join
      end

      query = self.class.model.select(q_cols).joins(q_joins.to_a).order(@order)

      @query.each do |key, val|
        filter = self.class.filters[key.to_s]

        if filter.is_a?(Proc)
          query = query.instance_exec(val, &filter)
        elsif (field = self.class.fields[key])
          query = query.where(field.path || key => val)
        else
          raise StandardError.new "Filter :#{key} not found for #{self.class}"
        end
      end

      query = query.distinct(@distinct) if @distinct
      query = query.distinct(@group) if @group
      query = query.offset(page_offset) if @page
      query = query.offset(@offset) if @offset
      query = query.limit(@limit) if @limit

      query
    end

    def sql
      query.to_sql
    end

    private

    def add_links(rows)
      return rows unless @includes

      @includes.each do |key, cols|
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
