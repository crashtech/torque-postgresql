# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Coder

      # This class represents an Record to be encoded, instead of a literal Array
      Record = Class.new(Array)

      class << self

        NEED_QUOTE_FOR = /[\\"(){}, \t\n\r\v\f]/m
        DELIMITER = ','

        # This method replace the +read_array+ method from PG gem
        # See https://github.com/ged/ruby-pg/blob/master/ext/pg_text_decoder.c#L177
        # for more information
        def decode(value)
          # TODO: Use StringScanner
          # See http://ruby-doc.org/stdlib-1.9.3/libdoc/strscan/rdoc/StringScanner.html
          _decode(::StringIO.new(value))
        end

        # This method replace the ++ method from PG gem
        # See https://github.com/ged/ruby-pg/blob/master/ext/pg_text_encoder.c#L398
        # for more information
        def encode(value)
          _encode(value)
        end

        private

          def _decode(stream)
            quoted = 0
            escaped = false
            result = []
            part = String.new

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
                when c == DELIMITER, c == '}', c == ')'

                  unless escaped
                    # Non-quoted empty string or NULL as extense
                    part = nil if quoted == 0 && ( part.length == 0 || part == 'NULL' )
                    result << part
                  end

                  return result unless c == DELIMITER

                  escaped = false
                  quoted = 0
                  part = String.new

                when c == '"'
                  quoted = 1
                when c == '{', c == '('
                  result << _decode(stream)
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
                if ( c == '"' || c == "'" ) && stream.getc != c
                  stream.pos -= 1
                  quoted = -1
                else
                  part << c
                end
              end

            end
          end

          def _encode(list)
            is_record = list.is_a?(Record)
            list.map! do |part|
              case part
              when NilClass
                is_record ? '' : 'NULL'
              when Array
                _encode(part)
              else
                _quote(part.to_s)
              end
            end

            result = is_record ? '(%s)' : '{%s}'
            result % list.join(DELIMITER)
          end

          def _quote(string)
            len = string.length

            # Fast results
            return '""' if len == 0
            return '"NULL"' if len == 4 && string == 'NULL'

            # Check if the string don't need quotes
            return string unless string =~ NEED_QUOTE_FOR

            # Use the original string escape function
            PG::Connection.escape_string(string).inspect
          end

      end

    end
  end
end
