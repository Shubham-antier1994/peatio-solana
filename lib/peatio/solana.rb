# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/enumerable'
require 'peatio'
require 'faraday'
# require 'faraday_middleware'
require 'json'

module Peatio
  module Solana
    Error = Class.new(StandardError)

    require_relative 'solana/version'
    require_relative 'solana/client'
    require_relative 'solana/blockchain'
    require_relative 'solana/wallet'
    require_relative 'solana/hooks'
  end
end

