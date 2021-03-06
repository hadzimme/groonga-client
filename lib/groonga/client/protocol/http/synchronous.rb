# Copyright (C) 2013  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2013-2014  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "net/http"

require "groonga/client/version"
require "groonga/client/empty-request"
require "groonga/client/protocol/error"

module Groonga
  class Client
    module Protocol
      class HTTP
        class Synchronous
          def initialize(host, port, options)
            @host = host
            @port = port
            @options = options
          end

          def send(command)
            begin
              Net::HTTP.start(@host, @port) do |http|
                response = send_request(http, command)
                case response
                when Net::HTTPSuccess, Net::HTTPBadRequest
                  yield(response.body)
                else
                  if response.body.start_with?("[[")
                    yield(response.body)
                  else
                    message =
                      "#{response.code} #{response.message}: #{response.body}"
                    raise Error.new(message)
                  end
                end
              end
            rescue SystemCallError, Timeout::Error
              raise WrappedError.new($!)
            end
            EmptyRequest.new
          end

          # @return [false] Always returns false because the current
          #   implementation doesn't support keep-alive.
          def connected?
            false
          end

          # Does nothing because the current implementation doesn't
          # support keep-alive. If the implementation supports
          # keep-alive, it close the opend connection.
          #
          # @overload close
          #   Closes synchronously.
          #
          #   @return [false] It always returns false because there is always
          #      no connection.
          #
          # @overload close {}
          #   Closes asynchronously.
          #
          #   @yield [] Calls the block when the opened connection is closed.
          #   @return [#wait] The request object. If you want to wait until
          #      the request is processed. You can send #wait message to the
          #      request.
          def close(&block)
            sync = !block_given?
            if sync
              false
            else
              yield
              EmptyRequest.new
            end
          end

          private
          def send_request(http, command)
            if command.name == "load"
              raw_values = command[:values]
              command[:values] = nil
              path = command.to_uri_format
              command[:values] = raw_values
              request = Net::HTTP::Post.new(path, headers)
              request.content_type = "application/json"
              request.body = raw_values
              http.request(request)
            else
              http.get(command.to_uri_format, headers)
            end
          end

          def headers
            {
              "user-agent" => @options[:user_agent],
            }
          end
        end
      end
    end
  end
end
