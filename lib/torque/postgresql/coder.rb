module Torque
  module PostgreSQL
    module Coder

      class << self

        # This method replace the +read_array+ method from PG gem
        # See https://github.com/ged/ruby-pg/blob/master/ext/pg_text_decoder.c#L177
        # for more information
        def decode(value, delimiter = ',')
          _decode(::StringIO.new(value), delimiter)
        end

        private

          def _decode(stream, delimiter)
            quoted = 0
            escaped = false
            result = []
            part = ''

            # Always start getting the non-collection character, the second char
            stream.getc if stream.pos == 0

            # Check for an empty list
            return result if %w[} )].include?(stream.getc)

            # If it's not an empty list, return one position before iterating
            stream.pos -= 1
            stream.each_char do |c|

              case
              when quoted < 1
                case
                when c == delimiter, c == '}', c == ')'

                  unless escaped
                    # Non-quoted empty string or NULL as extense
                    part = nil if quoted == 0 && ( part.length == 0 || part == 'NULL' )
                    result << part
                  end

                  return result unless c == delimiter

                  escaped = false
                  quoted = 0
                  part = ''

                when c == '"'
                  quoted = 1
                when c == '{', c == '('
                  result << _decode(stream, delimiter)
                  escaped = true
                else
                  part << c
                end
              when escaped
                escaped = false
                part << c
              when c == '\\'
                escaped = true
              when c == '"'
                if stream.getc == '"'
                  part << c
                else
                  stream.pos -= 1
                  quoted = -1
                end
              else
                part << c
              end

            end
          end

      end

    end
  end
end
