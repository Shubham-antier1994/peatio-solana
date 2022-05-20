# frozen_string_literal: true

module Peatio::Solana::Hooks
  class << self
    def check_compatibility
      if Peatio::Wallet::VERSION >= '2.0'
        [
          "Solana plugin was designed for work with 1.x. Wallet.",
          "You have #{Peatio::Solana::Wallet::VERSION}."
        ].join('\n').tap { |s| Kernel.abort s }
      end
    end

    def register
      Peatio::Blockchain.registry[:solana] = ::Peatio::Solana::Blockchain
      Peatio::Wallet.registry[:solana] = ::Peatio::Solana::Wallet
    end
  end

  if defined?(Rails::Railtie)
    require "peatio/solana/railtie"
  else
    check_compatibility
    register
  end
end
