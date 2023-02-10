module Wallet
  class Node
    MAXIMUM_GAP = 50

    getter conn
    @wallet : Wallet::Main
    @conn : HTTP::Client

    class RequestError < RuntimeError
    end

    class OutOfSync < RuntimeError
    end

    def initialize(@wallet)
      @conn = make_connection
    end

    def generate_address
      get("/wallet/generateaddress")
    end

    def read_int(json : JSON::Any?)
      json.nil? ? 0_i64 : json.as_i64
    end

    def read_int(json : JSON::Any, *field_names)
      read_int(json.dig?(*field_names))
    end

    def read_money(json : JSON::Any?)
      read_int(json) / 1000000
    end

    def read_money(json : JSON::Any, *field_names)
      read_money(json.dig?(*field_names))
    end

    def get_trx_balance(address)
      result = post("/wallet/getaccount", {"address" => address, "visible" => true})

      frozen_balance_for_bandwidth = 0.0
      if result["frozen"]?
        result["frozen"].as_a.each do |f|
          frozen_balance_for_bandwidth += read_money(f, "frozen_balance")
        end
      end

      frozen_balance_for_energy = read_money(result, "account_resource", "frozen_balance_for_energy", "frozen_balance")

      frozen = frozen_balance_for_bandwidth + frozen_balance_for_energy
      tron_power = frozen.to_i32

      votes_sum = 0
      if result["votes"]?
        result["votes"].as_a.each do |v|
          votes_sum += read_int(v, "vote_count")
        end
      end

      balance = read_money(result, "balance")

      return {
        "balance" => balance,
        "frozen" => frozen,
        "frozen_balance_for_energy" => frozen_balance_for_energy,
        "frozen_balance_for_bandwidth" => frozen_balance_for_bandwidth,
        "votes_used" => votes_sum,
        "tron_power" => tron_power
      }
    end

    def get_token_balance(address, contract)
      params = Wallet::Utils.tron_params(TronAddress.to_hex(address.not_nil!))
      result = post("/wallet/triggerconstantcontract", {
        "contract_address" => contract,
        "function_selector" => "balanceOf(address)",
        "parameter" => params,
        "owner_address" => address,
        "visible" => true
      })

      result["constant_result"]? ? result["constant_result"].as_a.first.as_s.to_i64(16) / 1000000 : 0_i64
    end

    def get_net_stats(address)
      result = post("/wallet/getaccountresource", {"address" => address, "visible" => true})

      net_limit = read_int(result, "freeNetLimit") + read_int(result, "NetLimit")
      net_used = read_int(result, "freeNetUsed") + read_int(result, "NetUsed")
      energy_limit = read_int(result, "EnergyLimit")
      energy_used = read_int(result, "EnergyUsed")

      return {
        "bandwidth_free" => net_limit - net_used,
        "bandwidth_limit" => net_limit,
        "energy_free" => energy_limit - energy_used,
        "energy_limit" => energy_limit,
        "visible" => true
      }
    end

    def get_unclaimed_rewards(address)
      result = post("/wallet/getReward", {"address" => address, "visible" => true})
      return read_money(result, "reward")
    end

    def get_contract_name(address)
      result = post("/wallet/triggerconstantcontract", {
        "owner_address" => "TQQg4EL8o1BSeKJY4MJ8TB8XK7xufxFBvK", # hardcode for unautorized call
        "contract_address" => address,
        "function_selector" => "name()",
        "visible" => true
      })

      result["constant_result"]? ? String.new(result["constant_result"].as_a.first.as_s.hexbytes).delete('\n') : nil
    end

    def transfer_trx(address : String, private_key : String, amount : Float64)
      amount = (amount * 1000000).to_i64
      result = post("/wallet/easytransferbyprivate", {
        "toAddress" => address,
        "privateKey" => private_key,
        "amount" => amount,
        "visible" => true
      })

      transaction_id = result["transaction"]? ? result["transaction"]["txID"].as_s : ""

      if result["result"]["result"]? && result["result"]["result"].as_bool? == true
        return "OK", "", transaction_id
      else
        return "FAILED", result["result"].to_json, transaction_id
      end
    end

    def transfer_token(address : String, private_key : String, contract : String, amount : Float64)
      amount = (amount * 1000000).to_i64
      parameter = Wallet::Utils.tron_params(TronAddress.to_hex(address), amount.to_s(16))

      make_transaction("/wallet/triggerconstantcontract", {
        "contract_address" => contract,
        "function_selector" => "transfer(address,uint256)",
        "parameter" => parameter,
        "owner_address" => @wallet.address.not_nil!,
        "fee_limit" => @wallet.settings["max_commission"].to_i64 * 1000000,
        "call_value" => 0,
        "visible" => true
      }, private_key)
    end

    def stake(address : String, amount : Float64, duration : Int32, resource : String, receiver : String?, private_key : String)
      amount = (amount * 1000000).to_i64

      make_transaction("/wallet/freezebalance", {
        "owner_address" => address,
        "frozen_balance" => amount,
        "frozen_duration" => duration,
        "resource" => resource,
        "receiver_address" => receiver == address ? nil : receiver,
        "visible" => true
      }, private_key, scoped: false)
    end

    def unstake(address : String, resource : String, receiver : String?, private_key : String)
      make_transaction("/wallet/unfreezebalance", {
        "owner_address" => address,
        "resource" => resource,
        "receiver_address" => receiver == address ? nil : receiver,
        "visible" => true
      }, private_key, scoped: false)
    end

    def claim_rewards(address : String, private_key : String)
      make_transaction("/wallet/withdrawbalance", {
        "owner_address" => address,
        "visible" => true
      }, private_key, scoped: false)
    end

    def get_witnesses_list
      get("/wallet/listwitnesses")
    end

    def get_brokerage(address : String)
      result = get("/wallet/getBrokerage", {"address" => address, "visible" => true})

      return read_int(result, "brokerage")
    end

    def vote_for_witness(address : String, witness : String, votes : Int32, private_key : String)
      if witness.starts_with? TronAddress::FIRST_BYTE
        witness = TronAddress.to_base58(witness)
      end

      make_transaction("/wallet/votewitnessaccount", {
        "owner_address" => address,
        "votes" => [
          {
            "vote_address" => witness,
            "vote_count" => votes
          }
        ],
        "visible" => true
      }, private_key, scoped: false)
    end

    def get_now_block
      get("/wallet/getnowblock")
    end

    def make_transaction(path, params, private_key, scoped = true)
      transaction = post(path, params)

      if scoped
        if transaction["transaction"]?.nil?
          return "FAILED", transaction.to_json, nil
        end
        transaction = transaction["transaction"]
      end

      if transaction["txID"]?.nil?
        return "FAILED", transaction.to_json, nil
      end

      id = transaction["txID"].as_s

      if transaction["ret"]? && transaction["ret"].as_a.first.as_h.any?
        return "FAILED", transaction["result"]["message"].as_s, id
      end

      signed = sign_transaction(transaction, private_key)
      sended = send_transaction(signed)

      id = sended["txid"].as_s

      if sended["result"]? && sended["result"].as_bool == true
        return "OK", "", id
      else
        return "FAILED", sended.to_json, id
      end
    end

    def sign_transaction(transaction : JSON::Any, private_key : String)
      post("/wallet/gettransactionsign", {
        "transaction" => transaction,
        "privateKey" => private_key,
      })
    end

    def send_transaction(transaction : JSON::Any)
      post("/wallet/broadcasttransaction", transaction)
    end

    def status
      node_block = get_now_block.dig("block_header", "raw_data", "number").as_i64
      real_block = get_tronscan_block

      if real_block
        diff = (real_block - node_block).abs
        if diff > MAXIMUM_GAP
          raise OutOfSync.new("node is out of sync, having block #{node_block} while Tronscan block is #{real_block}, diff is #{diff}")
        end
      else
        @wallet.prompt.warn("Cannot get current block from Tronscan! Your node can be out of sync, be careful, check it manually with `block` command!")
      end

      @wallet.connected = true
    rescue error
      disconnect_with_warning(error)
    end

    def get_tronscan_block
      response = HTTP::Client.get("https://apilist.tronscanapi.com/api/system/status")
      JSON.parse(response.body).dig("full", "block").as_i64
    rescue
      nil
    end

    def reconnect
      @conn = make_connection
    end

    def make_connection
      url = @wallet.settings["node_url"]

      unless url.starts_with? /https?:\/\//
        url = if url =~ /^\d+\.\d+\.\d+\.\d+(?::\d+)?$/
          "http://#{url}"
        else
          "https://#{url}"
        end
      end

      connection = HTTP::Client.new URI.parse url
      connection.connect_timeout = 5
      return connection
    end

    def get(path, params = nil)
      body = params.to_json if params

      response = begin
        @conn.get(path, body: body)
      rescue error
        error_while_request(error)
      end

      JSON.parse(response.body)
    end

    def post(path, params)
      body = params.to_json

      response = begin
        @conn.post(path, body: body)
      rescue error
        error_while_request(error)
      end

      JSON.parse(response.body)
    end

    def error_while_request(error)
      disconnect_with_warning(error)
      raise RequestError.new
    end

    def disconnect_with_warning(error)
      problem = error.is_a?(OutOfSync) ? "It's dangerous to" : "Cannot"
      @wallet.prompt.error("#{problem} connect to #{@wallet.settings["node_url"]} (#{error.message})")
      @wallet.prompt.warn("\nUse `connect` command to try again or")
      @wallet.prompt.warn("try another node from the list (ctrl+click):")
      @wallet.prompt.warn("\nhttps://tronprotocol.github.io/documentation-en/developers/official-public-nodes/")
      @wallet.prompt.warn("\nDo not forget the port, for example: `connect 3.225.171.164:8090`")
      @wallet.prompt.warn("Scheme is optional (`http` for IP and `https` for domain by default)")
      @wallet.connected = false
    end
  end
end