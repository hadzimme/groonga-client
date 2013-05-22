# -*- coding: utf-8 -*-
#
# Copyright (C) 2013  Haruka Yoshihara <yoshihara@clear-code.com>
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

require "socket"
require "groonga/client"

class TestClient < Test::Unit::TestCase
  module ClientTests
    def test_without_columns_in_responses
      options = {:host => @address, :port => @port, :protocol => @protocol}
      @response_header = groonga_response_header
      @response_body = '{"key":"value"}'

      expected_body = {"key" => "value"}

      Groonga::Client.open(options) do |client|
        response = client.status

        assert_header(response)
        assert_equal(expected_body, response.body)
      end
    end

    def test_with_columns_in_responses
      options = {:host => @address, :port => @port, :protocol => @protocol}
      @response_header = groonga_response_header
      @response_body = <<-JSON
[[["name","ShortText"],
["age","UInt32"]],
["Alice",32],
["Bob",21]]
JSON
      expected_table_infos = [
        {:name => "Alice", :age => 32},
        {:name => "Bob", :age => 21}
      ]

      Groonga::Client.open(options) do |client|
        response = client.table_list
        actual_table_infos = response.body.collect do |value|
          value.table_info
        end

        assert_header(response)
        assert_equal(expected_table_infos, actual_table_infos)
      end
    end

    def test_with_parameters
      options = {:host => @address, :port => @port, :protocol => @protocol}
      @response_header = groonga_response_header
      @response_body = "100"
      expected_body = 100

      Groonga::Client.open(options) do |client|
        response = client.cache_limit(:max => 4)

        assert_header(response)
        assert_equal(expected_body, response.body)
      end
    end

    def test_not_json_as_response
      options = {:host => @address, :port => @port, :protocol => @protocol}
      @response_header = nil
      @response_body = "table_create TEST_TABLE TABLE_NO_KEY"
      expected_body = @response_body

      Groonga::Client.open(options) do |client|
        response = client.dump
        assert_nil(response.header)
        assert_equal(expected_body, response.body)
      end
    end

    def groonga_response_header
      [0, "START_TIME", "ELAPSED_TIME"]
    end

    def assert_header(response)
      normalized_header = normalize_header(response.header)
      assert_equal(groonga_response_header, normalized_header)
    end
  end

  class TestGQTP < self
    def setup
      @address = "127.0.0.1"
      @server = TCPServer.new(@address, 0)
      @port = @server.addr[1]
      @protocol = :gqtp

      @response_body = nil
      @thread = Thread.new do
        client = @server.accept
        @server.close

        header = GQTP::Header.parse(client.read(GQTP::Header.size))
        client.read(header.size)

        response_header = GQTP::Header.new
        response_header.size = @response_body.bytesize

        client.write(response_header.pack)
        client.write(@response_body)
        client.close
      end
    end

    def teardown
      @thread.kill
    end

    def normalize_header(header)
      start_time = header[1]
      elapsed_time = header[2]
      header[1] = "START_TIME" if /\A[\d\.]+\z/ =~ start_time.to_s
      header[2] = "ELAPSED_TIME" if /\A[\d\.]+\z/ =~ elapsed_time.to_s
      header
    end

    include ClientTests
  end

  class TestHTTP < self
    def setup
      @address = "127.0.0.1"
      @server = TCPServer.new(@address, 0)
      @port = @server.addr[1]
      @protocol = :http

      @response_body = nil
      @thread = Thread.new do
        client = @server.accept
        @server.close
        if @response_header.nil?
          body = @response_body
        else
          body = "[#{@response_header},\n#{@response_body}]"
        end
        header = <<-EOH
HTTP/1.1 200 OK
Connection: close
Content-Type: application/json
Content-Length: #{body.bytesize}

EOH
        client.write(header)
        client.write(body)
        client.close
      end
    end

    def normalize_header(header)
      header
    end

    include ClientTests
  end
end
