module Wallet
  class Node
    getter conn
    @wallet : Wallet::Main
    @conn : HTTP::Client

    def initialize(@wallet)
      uri = URI.parse @wallet.settings["node_url"]
      @conn = HTTP::Client.new uri
      @conn.connect_timeout = 5
    end

    def generate_address
      res = @conn.get("/wallet/generateaddress")
      return JSON.parse(res.body)
    end

    def get_balance(address)
      res = @conn.post("/wallet/getaccount", body: {"address" => address, "visible" => true}.to_json)
      body = JSON.parse(res.body)

      balance = body["balance"]? ? JSON.parse(res.body)["balance"].as_i64 : 0_i64
      return balance / 1000000
    end

    def get_token_balance(address, contract)
      params = Wallet::Utils.tron_params(TronAddress.to_hex(address.not_nil!))
      res = @conn.post("/wallet/triggerconstantcontract", body: {
        "contract_address" => contract,
        "function_selector" => "balanceOf(address)",
        "parameter" => params,
        "owner_address" => address,
        "visible" => true
      }.to_json)

      body = JSON.parse(res.body)
      balance = body["constant_result"]? ? body["constant_result"].as_a.first.as_s.to_i64(16) : 0_i64
      return balance / 1000000
    end

    def get_contract_name(address)
      res = @conn.post("/wallet/triggerconstantcontract", body: {
        "owner_address" => "TQQg4EL8o1BSeKJY4MJ8TB8XK7xufxFBvK", # hardcode for unautorized call
        "contract_address" => address,
        "function_selector" => "name()",
        "visible" => true
      }.to_json)

      body = JSON.parse(res.body)
      name = body["constant_result"]? ? String.new(body["constant_result"].as_a.first.as_s.hexbytes).delete('\n') : nil

      return name
    end

    def transfer(address : String, private_key : String, amount : Float64)
      amount = (amount * 1000000).to_i64
      res = @conn.post("/wallet/easytransferbyprivate", body: {
        "visible" => true,
        "toAddress" => address,
        "privateKey" => private_key,
        "amount" => amount
      }.to_json)

      body = JSON.parse(res.body)
      transaction_id = body["transaction"]? ? body["transaction"]["txID"].as_s : ""

      if body["result"]["result"]? && body["result"]["result"].as_bool? == true
        return "OK", "", transaction_id
      else
        return "FAILED", body["result"].to_json, transaction_id
      end
    end

    def transfer_token(address : String, private_key : String, contract : String, amount : Float64)
      amount = (amount * 1000000).to_i64
      transaction = create_trc20_transaction(from: @wallet.address.not_nil!, to: address, contract: contract, amount: amount)

      transaction_id = transaction["transaction"]? ? transaction["transaction"]["txID"].as_s : ""

      if !transaction["transaction"]?
        return "FAILED", transaction["result"]["message"].as_s, transaction_id
      elsif transaction["transaction"]["ret"].as_a.first.as_h.any?
        return "FAILED", transaction["result"]["message"].as_s, transaction_id
      else
        signed = sign_transaction(transaction["transaction"], private_key)
        sended = send_transaction(signed)
        if sended["result"]? && sended["result"].as_bool == true
          return "OK", "", sended["txid"].as_s
        else
          return "FAILED", sended.to_json, sended["txid"].as_s
        end
      end
    end

    def create_trc20_transaction(from : String, to : String,  contract : String, amount : Int64)
      params = Wallet::Utils.tron_params(TronAddress.to_hex(to), amount.to_s(16))

      body = {
        "contract_address" => contract,
        "function_selector" => "transfer(address,uint256)",
        "parameter" => params,
        "owner_address" => from,
        "fee_limit" => @wallet.settings["max_commission"].to_i64 * 1000000,
        "call_value" => 0,
        "visible" => true
      }

      res = @conn.post("/wallet/triggerconstantcontract", body: body.to_json)
      return JSON.parse(res.body)
    end

    def create_transaction(from : String, to : String, amount : Int64)
      res = @conn.post("/wallet/createtransaction", body: {
        "to_address" => TronAddress.to_hex(to),
        "owner_address" => TronAddress.to_hex(from),
        "amount" => amount
      }.to_json)

      return JSON.parse(res.body)
    end

    def sign_transaction(transaction : JSON::Any, private_key : String)
      body = {
        "transaction" => transaction,
        "privateKey" => private_key,
      }.to_json

      res = @conn.post("/wallet/gettransactionsign", body: body)

      return JSON.parse(res.body)
    end

    def send_transaction(transaction : JSON::Any)
      res = @conn.post("/wallet/broadcasttransaction", body: transaction.to_json)

      return JSON.parse(res.body)
    end

    def get_now_block
      res = @conn.get("/wallet/getnowblock")

      return JSON.parse(res.body)
    end

    def status
      @conn.get("/")
      @wallet.connected = true
    rescue error
      @wallet.prompt.error("Cannot connect to #{@wallet.settings["node_url"]} (#{error.message})")
      @wallet.connected = false
    end

    def reconnect
      uri = URI.parse @wallet.settings["node_url"]
      @conn = HTTP::Client.new uri
    end
  end
end