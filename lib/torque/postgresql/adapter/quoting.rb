module Torque
  module PostgreSQL
    module Adapter
      module Quoting

        # Quotes type names for use in SQL queries.
        def quote_type_name(name)
          PGconn.quote_ident(name.to_s)
        end

      end
    end
  end
end
