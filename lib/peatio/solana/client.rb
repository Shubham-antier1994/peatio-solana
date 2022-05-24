# frozen_string_literal: true

require 'memoist'
require 'faraday'
require 'better-faraday'

module Peatio
  module Solana
    class Client
      Error = Class.new(StandardError)
      ConnectionError = Class.new(Error)

      @@API_ENDPOINT = 'http://localhost:3001/api/solana'.freeze

      class ResponseError < Error
        def initialize(code, msg)
          @code = code
          @msg = msg
        end

        def message
          "#{@msg} (#{@code})"
        end
      end

      extend Memoist

      def initialize(endpoint)
        @json_rpc_endpoint = URI.parse(endpoint)
        @endpoint = URI.parse(endpoint)
      end


      def json_rpc(method, params=[])
        response = post(method, params)
        response.assert_2xx!
        response = JSON.parse(response.body)

        response["error"].tap do |e|
          raise ResponseError.new(e["code"], e["message"]) if e
        end

        response.fetch("result")
      rescue Faraday::Error => e
        raise ConnectionError, e
      end

      def rest_api(verb, path, data = nil)
        args = [@endpoint.to_s + "/#{path}"]

        if data
          if %i[post put patch].include?(verb)
            args << data.compact.to_json
            args << { 'Content-Type' => 'application/json' }
          else
            args << data.compact
            args << {}
          end
        else
          args << nil
          args << {}
        end

        args.last['Accept'] = 'application/json'
        response = Faraday.send(verb, *args)
        response.assert_success!
        response = JSON.parse(response.body)
        response['error'].tap { |error| raise ResponseError.new(error) if error }
        Rails.logger.warn{"===============response.dig('data')=================#{response.dig('data')}"}
        response.dig('data').deep_symbolize_keys!
      rescue Faraday::Error => e
        if e.is_a?(Faraday::ConnectionFailed) || e.is_a?(Faraday::TimeoutError)
          raise ConnectionError, e
        else
          raise ConnectionError, JSON.parse(e.response.body)['message']
        end
      end

      private

      def post(method, params)
        connection.post("", {jsonrpc: "2.0", method: method, params: params, id: 1}.to_json,
                        { "accept": "application/json", "content-type": "application/json" })
      end

      def connection
        @connection ||= Faraday.new(@json_rpc_endpoint) do |f|
          f.adapter :net_http_persistent, pool_size: 100
        end.tap do |connection|
          unless @json_rpc_endpoint.user.blank?
            connection.basic_auth(@json_rpc_endpoint.user,
                                  @json_rpc_endpoint.password)
          end
        end
      end
    end
  end
end
