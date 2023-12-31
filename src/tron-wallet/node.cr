module Wallet
  class Node
    MAXIMUM_GAP = 50
    TRX_TO_SUN = 1000000

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
      ## Does not work, insecure
      # get("/wallet/generateaddress")

      ## Correct way: https://developers.tron.network/docs/account
      private_key = Random::Secure.hex(32)
      context = Secp256k1::Context.new
      key = Secp256k1::Key.new Secp256k1::Num.new(private_key)
      bytes = key.public_bytes
      bytes = bytes[1..] if bytes.size == 65 # 5 TRX lost because of this undocumented behavior
      keccak = Secp256k1::Util.keccak(bytes, 256)
      hex = TronAddress::FIRST_BYTE + keccak.hex[-40..]
      address = TronAddress.to_base58(hex)
      return address, private_key
    end

    def read_int(json : JSON::Any?)
      json.nil? ? 0_i64 : json.as_i64
    end

    def read_int(json : JSON::Any, *field_names)
      read_int(json.dig?(*field_names))
    end

    def read_money(json : JSON::Any?)
      read_int(json) / TRX_TO_SUN
    end

    def read_money(json : JSON::Any, *field_names)
      read_money(json.dig?(*field_names))
    end

    def get_trx_balance(address)
      result = post("/wallet/getaccount", {"address" => address, "visible" => true})

      frozen_balance_for_energy = 0.0
      frozen_balance_for_bandwidth = 0.0

      if result["frozenV2"]?
        result["frozenV2"].as_a.each do |field|
          amount = read_money(field, "amount")

          case field["type"]?
          when "ENERGY"
            frozen_balance_for_energy += amount
          when "BANDWIDTH", nil # Yes, empty field means bandwidth
            frozen_balance_for_bandwidth += amount
          when "TRON_POWER"
            # Do nothing: there is no `amount` field!
          end
        end
      end

      frozen = frozen_balance_for_bandwidth + frozen_balance_for_energy

      frozen_v1_balance_for_bandwidth = 0.0
      if result["frozen"]?
        result["frozen"].as_a.each do |field|
          frozen_v1_balance_for_bandwidth += read_money(field, "frozen_balance")
        end
      end

      frozen_v1_balance_for_energy = read_money(result, "account_resource", "frozen_balance_for_energy", "frozen_balance")

      frozen_v1 = frozen_v1_balance_for_bandwidth + frozen_v1_balance_for_energy

      tron_power = frozen.to_i32 + frozen_v1.to_i32

      votes_sum = 0
      if result["votes"]?
        result["votes"].as_a.each do |v|
          votes_sum += read_int(v, "vote_count")
        end
      end

      balance = read_money(result, "balance")

      return {
        balance: balance,
        frozen: frozen,
        frozen_balance_for_energy: frozen_balance_for_energy,
        frozen_balance_for_bandwidth: frozen_balance_for_bandwidth,
        frozen_v1: frozen_v1,
        frozen_v1_balance_for_energy: frozen_v1_balance_for_energy,
        frozen_v1_balance_for_bandwidth: frozen_v1_balance_for_bandwidth,
        votes_used: votes_sum,
        tron_power: tron_power
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

      result["constant_result"]? ? result["constant_result"].as_a.first.as_s.to_i64(16) / TRX_TO_SUN : 0_f64
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

    def get_withdrawable_balance(address)
      result = post(
        "/wallet/getcanwithdrawunfreezeamount",
        {
          "owner_address" => address,
          "visible" => true
        }
      )
      return read_money(result, "amount")
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
      amount = (amount * TRX_TO_SUN).to_i64

      ## Does not work, insecure
      # result = post("/wallet/easytransferbyprivate", {
      #   "toAddress" => address,
      #   "privateKey" => private_key,
      #   "amount" => amount,
      #   "visible" => true
      # })

      sign_and_send(post("/wallet/createtransaction", {
        "to_address" => address,
        "owner_address" => @wallet.address.not_nil!,
        "amount" => amount,
        "visible" => true
      }), private_key)
    end

    def prepare_token_transfer(address : String, contract : String, amount : Float64, estimate_fee = false)
      method = estimate_fee ? "triggerconstantcontract" : "triggersmartcontract"

      amount = (amount * TRX_TO_SUN).to_i64
      parameter = Wallet::Utils.tron_params(TronAddress.to_hex(address), amount.to_s(16))
      fee_limit = @wallet.settings["max_commission"].to_i64 * TRX_TO_SUN

      post("/wallet/#{method}", {
        "contract_address" => contract,
        "function_selector" => "transfer(address,uint256)",
        "parameter" => parameter,
        "owner_address" => @wallet.address.not_nil!,
        "fee_limit" => fee_limit,
        "call_value" => 0,
        "visible" => true
      })
    end

    def stake(address : String, amount : Float64, resource : String, private_key : String)
      amount = (amount * TRX_TO_SUN).to_i64

      make_transaction("/wallet/freezebalancev2", {
        "owner_address" => address,
        "frozen_balance" => amount,
        "resource" => resource,
        "visible" => true
      }, private_key)
    end

    def unstake(address : String, amount : Float64, resource : String, private_key : String)
      amount = (amount * TRX_TO_SUN).to_i64
      make_transaction("/wallet/unfreezebalancev2", {
        "owner_address" => address,
        "unfreeze_balance" => amount,
        "resource" => resource,
        "visible" => true
      }, private_key)
    end

    def unstake_v1(address : String, resource : String, receiver : String?, private_key : String)
      make_transaction("/wallet/unfreezebalance", {
        "owner_address" => address,
        "resource" => resource,
        "receiver_address" => receiver == address ? nil : receiver,
        "visible" => true
      }, private_key)
    end

    def withdraw_unstaked_trx(address : String, private_key : String)
      make_transaction("/wallet/withdrawexpireunfreeze", {
        "owner_address" => address,
        "visible" => true
      }, private_key)
    end

    def claim_rewards(address : String, private_key : String)
      make_transaction("/wallet/withdrawbalance", {
        "owner_address" => address,
        "visible" => true
      }, private_key)
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
      }, private_key)
    end

    def get_now_block
      get("/wallet/getnowblock")
    end

    def get_energy_price
      get("/wallet/getenergyprices")["prices"].as_s.split(',')[-1].split(':')[1].to_i64 / TRX_TO_SUN
    end

    def get_bandwidth_price
      get("/wallet/getbandwidthprices")["prices"].as_s.split(',')[-1].split(':')[1].to_i64 / TRX_TO_SUN
    end

    def make_transaction(path, params, private_key)
      transaction = post(path, params)
      sign_and_send(transaction, private_key)
    end

    def sign_and_send(transaction, private_key)
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
        sleep 5 # Waiting for the info can be retrieved
        return get_transaction(id)
      else
        return "FAILED", sended.to_json, id
      end
    end

    def sign_transaction(transaction : JSON::Any, private_key : String)
      ## Does not work, insecure
      # post("/wallet/gettransactionsign", {
      #   "transaction" => transaction,
      #   "privateKey" => private_key,
      # })

      context = Secp256k1::Context.new
      key = Secp256k1::Key.new Secp256k1::Num.new(private_key)
      id = transaction["txID"].as_s
      sig = context.sign key, Secp256k1::Num.new(id)

      {
        "signature" => [sig.compact],
        "txID" => id,
        "raw_data" => transaction["raw_data"],
        "raw_data_hex" => transaction["raw_data_hex"],
        "visible" => true
      }
    end

    def send_transaction(transaction)
      post("/wallet/broadcasttransaction", transaction)
    end

    def get_transaction(id)
      info = post("/wallet/gettransactioninfobyid", {"value": id})

      energy_used = read_int(info, "receipt", "energy_usage")
      sun_burned_for_energy = read_int(info, "receipt", "energy_fee")
      bandwidth_used = read_int(info, "receipt", "net_usage")
      sun_burned_for_bandwidth = read_int(info, "receipt", "net_fee")
      trx_burned = (sun_burned_for_energy + sun_burned_for_bandwidth) / TRX_TO_SUN

      fee_elements = [
        ("#{trx_burned.format} TRX" if trx_burned > 0),
        ("#{energy_used.format} energy" if energy_used > 0),
        ("#{bandwidth_used.format} bandwidth" if bandwidth_used > 0)
      ].compact

      fee = "Fee: #{fee_elements.any? ? fee_elements.join(", ") : "none"}"

      maybe_result = info.dig? "receipt", "result"
      if maybe_result
        result = maybe_result.as_s
      else
        if fee_elements.any?
          return "OK", "#{fee}\nUse `transaction` command later if you expect any other details", id
        else
          return "OK", "But no additional info available yet...\nUse `transaction` command later", id
        end
      end

      if result == "SUCCESS"
        return "OK", fee, id
      else
        details = if info["resMessage"]?
          String.new TronAddress.hex_to_bytes info["resMessage"].as_s
        else
          "not provided"
        end

        message = "Result: #{result}\nDetails: #{details}\n#{fee}"

        return "FAILED", message, id
      end
    end

    def status
      node_block = get_now_block.dig("block_header", "raw_data", "number").as_i64

      unless ENV["TRON_WALLET_CHECK_IS_NODE_OUT_OF_SYNC"]? == "false"
        real_block = get_tronscan_block

        if real_block
          diff = (real_block - node_block).abs
          if diff > MAXIMUM_GAP
            raise OutOfSync.new("node is out of sync, having block #{node_block} while Tronscan block is #{real_block}, diff is #{diff}")
          end
        else
          @wallet.prompt.warn("Cannot get current block from TronScan! Your node can be out of sync, be careful, check it manually with `block` command!")
        end
      end

      @wallet.connected = true
    rescue RequestError
      # Error message already shown in `error_while_request`
      false
    rescue error : OutOfSync
      disconnect_with_warning(error)
      false
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
      exec("GET", path, body)
    end

    def post(path, params)
      body = params.to_json
      exec("POST", path, body)
    end

    def exec(method, path, body)
      @wallet.debug!("request #{path} with body: #{body}")

      begin
        response = @conn.exec(method, path, body: body)
      rescue error
        error_while_request(error)
      end

      @wallet.debug!("response #{response.status} with body: #{response.body}")

      begin
        JSON.parse(response.body)
      rescue error
        error_while_parse(response.body)
      end
    end

    def error_while_request(error)
      disconnect_with_warning(error)
      raise RequestError.new
    end

    def error_while_parse(body)
      @wallet.prompt.error("Cannot parse response body! Valid JSON expected, but got this:\n")
      @wallet.prompt.warn(body)
      raise RequestError.new
    end

    def disconnect_with_warning(error)
      problem = error.is_a?(OutOfSync) ? "It's dangerous to" : "Cannot"
      @wallet.prompt.error("#{problem} connect to #{@wallet.settings["node_url"]} (#{error.message})")
      if error.is_a?(OutOfSync)
        @wallet.prompt.error("You can set `TRON_WALLET_CHECK_IS_NODE_OUT_OF_SYNC` environment variable to `false` to disable this check.")
      end
      @wallet.prompt.warn("\nUse `connect` command to try again or")
      @wallet.prompt.warn("try another node from the list (ctrl+click):")
      @wallet.prompt.warn("\nhttps://tronprotocol.github.io/documentation-en/developers/official-public-nodes/")
      @wallet.prompt.warn("\nDo not forget the port, for example: `connect 3.225.171.164:8090`")
      @wallet.prompt.warn("Scheme is optional (`http` for IP and `https` for domain by default)")
      @wallet.connected = false
    end
  end
end