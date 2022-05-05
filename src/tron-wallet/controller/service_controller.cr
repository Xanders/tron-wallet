module Wallet
  module ServiceController
    def help(args)
      @wallet.prompt.say("
• wallet: list wallet commands
    # all wallet commands linked to root namespace
    # you can send all commands below without `wallet`
    login (*account_name): login into account
    logout: log out from account
    list: list available accounts
    create (*account_name): create new account
    import (*account_name (*address)): import account
    delete: delete current account
    address (*account_name): show account address
    history (*account_name): provide a link to transactions history
    backup (*account_name): show account address & private key
    balance (*account_name): show account balance
    send: send TRX or TRC20 token
    stake: stake TRX to gain energy or bandwidth
    claim: claim TRX for voting rewards
    rename (*old_name (*new_name)): change account name
    change_password (*account_name): change account password

• contracts: list contracts commands
    list: list available contracts
    create (*contract_name (*contract_address)): add new TRC-20 contract
    delete (*contract_name): delete contract

• book: list addressbook commands
    list: list available book addresses
    create: add new record to addressbook
    delete: delete addressbook record

• settings: list settings commands
    show: show application settings
    edit: edit application settings

• connect (*node_url): try to connect to the node
• block: print current block number
• help: print all supported commands
• exit: shutdown the REPL


")
    end

    def connect(args)
      current_node_url = @wallet.db.get_settings["node_url"]

      if args.any?
        new_node_url = args.shift
        @wallet.db.update_settings(node_url: new_node_url)
        @wallet.prompt.warn("Node URL was changed in settings from #{current_node_url} to #{new_node_url}")
        current_node_url = new_node_url
        @wallet.node.reconnect
      end

      if @wallet.node.status
        @wallet.prompt.say("Succesfully connnected to #{current_node_url}")
      end
    end

    def block(args)
      return unless connected?

      res = @wallet.node.get_now_block
      id = res["blockID"].as_s
      number = res.dig("block_header", "raw_data", "number").as_i64
      @wallet.prompt.say("Number: #{number}")
      @wallet.prompt.say("ID: #{id}")
    rescue Wallet::Node::RequestError
      # OK, it is safe
    end
  end
end