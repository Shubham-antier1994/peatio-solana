module Peatio
  module Solana
    # TODO: Processing of unconfirmed transactions from mempool isn't supported now.
    class Blockchain < Peatio::Blockchain::Abstract
      #include CashAddressFormat

      DEFAULT_FEATURES = { case_sensitive: true, cash_addr_format: false }.freeze
      SYSTEM_PROGRAMME = "11111111111111111111111111111111".freeze

      def initialize(custom_features = {})
        @features = DEFAULT_FEATURES.merge(custom_features).slice(*SUPPORTED_FEATURES)
        @settings = {}
      end

      def configure(settings = {})
        # Clean client state during configure.
        @client = nil

        @settings.merge!(settings.slice(*SUPPORTED_SETTINGS))
      end

      def fetch_confirmed_block!(start_block_number, end_block_number)
        client.json_rpc(:getBlocks, [start_block_number, end_block_number])
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      def fetch_block!(block_number)
        client.json_rpc(:getBlock, [block_number, { "encoding": "json", "rewards": false }])
          &.fetch('transactions')&.each_with_object([]) do |tx, txs_array|
          txs = build_transaction(tx).map do |ntx|
            Peatio::Transaction.new(ntx.merge(block_number: block_number))
          end
          txs_array.append(*txs)
        end.yield_self { |txs_array| Peatio::Block.new(block_number, txs_array || []) }
      rescue Client::Error => e
        if e.message.include?('was skipped, or missing due to ledger jump to recent snapshot')
          Peatio::Block.new(block_number, [])
        else
          raise Peatio::Blockchain::ClientError, e
        end

      end

      def fetch_transaction(transaction)
        transaction_hash = client.json_rpc(:getTransaction, [transaction.hash, 'json'])

        tx = settings_fetch(:currencies).each_with_object([]) do |currency, formatted_txs|
          formatted_txs << { hash: transaction_hash['transaction']['signatures'][0],
                             to_address: normalize_address(transaction_hash['transaction']['message']['accountKeys'][1]),
                             status: 'success',
                             block_number: transaction.block_number,
                             fee_currency_id: transaction.currency_id,
                             currency_id: transaction.currency_id,
                             amount: convert_from_base_unit((transaction_hash['meta']['postBalances'][1] - transaction_hash['meta']['preBalances'][1]), currency),
                             fee: convert_from_base_unit(transaction_hash['meta']['fee'], currency)
          }
        end
        if tx.present?
          Peatio::Transaction.new(tx[0])
        else
          Peatio::Transaction.new
        end
      end

      def latest_block_number
        client.json_rpc(:getSlot)
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      def load_balance_of_address!(address, _currency_id)
        address_with_balance = client.json_rpc(:getBalance, [address]).fetch('value').to_d

        # address_with_balance = client.json_rpc(:getBalance)
        #                              .flatten(1)
        #                              .find { |addr| addr[0] == normalize_address(address) }

        if address_with_balance.blank?
          raise Peatio::Blockchain::UnavailableAddressBalanceError, normalize_address(address)
        end

        address_with_balance
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      private

      def build_transaction(tx_hash)
        settings_fetch(:currencies).each_with_object([]) do |currency, formatted_txs|
          formatted_txs << { hash: tx_hash['transaction']['signatures'][0],
                             to_address: normalize_address(tx_hash['transaction']['message']['accountKeys'][1]),
                             status: 'success',
                             currency_id: currency[:id],
                             amount: convert_from_base_unit((tx_hash['meta']['postBalances'][1] - tx_hash['meta']['preBalances'][1]), currency) }
        end
      end



      def convert_from_base_unit(value, currency)
        value.to_d / currency.fetch(:base_factor).to_d
      end

      def client
        @client ||= Client.new(settings_fetch(:server))
      end

      def normalize_address(address)
        address
      end

      def settings_fetch(key)
        @settings.fetch(key) { raise Peatio::Blockchain::MissingSettingError, key.to_s }
      end
    end
  end
end
