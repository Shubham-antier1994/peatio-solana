module Peatio
  module Solana
    class Wallet < Peatio::Wallet::Abstract
      #include CashAddressFormat

      DEFAULT_FEATURES = { skip_deposit_collection: false }.freeze
      SUPPORTED_FEATURES = %i[skip_deposit_collection].freeze

      def initialize(custom_features = {})
        @features = DEFAULT_FEATURES.merge(custom_features).slice(*SUPPORTED_FEATURES)
        @settings = {}
      end

      def configure(settings = {})
        # Clean client state during configure.
        @client = nil

        @settings.merge!(settings.slice(*SUPPORTED_SETTINGS))

        @wallet = @settings.fetch(:wallet) do
          raise Peatio::Wallet::MissingSettingError, :wallet
        end.slice(:uri, :address, :secret)

        @currency = @settings.fetch(:currency) do
          raise Peatio::Wallet::MissingSettingError, :currency
        end.slice(:id, :base_factor, :options)
      end

      def create_address!(_options = {})
        client.rest_api(:get, 'generateAddress')
      rescue Solana::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      def create_transaction!(transaction, options = {})
        Rails.logger.warn{"===============transaction=================#{transaction.inspect}"}
        amount = convert_to_base_unit(transaction.amount)
        Rails.logger.warn{"===============amount=================#{amount}"}
        txid = client.rest_api(:post, 'generateTransaction', {
          toAddress: normalize_address(transaction.to_address.to_s),
          amtTobeTransferred: amount.to_s,
          fromMnemonics: wallet_passphrase
        }.compact).fetch(:txnhash)

        transaction.hash = txid
        Rails.logger.warn{"===============txid=================#{txid}"}
        transaction
      rescue Solana::Client::Error => e
        Rails.logger.warn{"===============error=================#{e}"}
        raise Peatio::Wallet::ClientError, e
      end

      def load_balance!
        response = client.rest_api(:post, 'getAccountBalance', { address: wallet_address })
        convert_from_base_unit(response.fetch(:balance))
      rescue Solana::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      private

      def currency_id
        @currency.fetch(:id) { raise Peatio::Wallet::MissingSettingError, :id }
      end

      def client
        uri = @wallet.fetch(:uri) { raise Peatio::Wallet::MissingSettingError, :uri }
        @client ||= Client.new(uri)
      end

      def wallet_passphrase
        @wallet.fetch(:secret)
      end

      def wallet_id
        @wallet.fetch(:wallet_id)
      end

      def wallet_address
        @wallet.fetch(:address)
      end

      def normalize_address(address)
        address
      end

      def normalize_txid(txid)
        txid.downcase
      end

      def convert_from_base_unit(value)
        value.to_d / @currency.fetch(:base_factor)
      end

      def convert_to_base_unit(value)
        x = value.to_d * @currency.fetch(:base_factor)
        unless (x % 1).zero?
          raise Peatio::WalletClient::Error,
                'Failed to convert value to base (smallest) unit because it exceeds the maximum precision: ' \
                "#{value.to_d} - #{x.to_d} must be equal to zero."
        end
        x.to_i
      end

    end
  end
end
