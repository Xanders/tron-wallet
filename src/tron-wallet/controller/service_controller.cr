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
    backup (*account_name): show account address & private key
    balance (*account_name): show account balance
    send: send TRX or TRC20 token

• contracts: list contracts commands
    list: list available contracts
    add (*contract_name (*contract_address)): add new TRC-20 contract
    delete (*contract_name): delete contract

• book: list addressbook commands
    list: list available book addresses
    add: add new record to addressbook
    delete: delete addressbook record

• settings: list settings commands
    show: show application settings
    edit: edit application settings

• block: print current block number
• help: print all supported commands


")
    end

    def block(args)
      res = @wallet.node.get_now_block
      id = res["blockID"].as_s
      number = res.dig("block_header", "raw_data", "number").as_i64
      @wallet.prompt.say("Number: #{number}")
      @wallet.prompt.say("ID: #{id}")
    end
  end
end