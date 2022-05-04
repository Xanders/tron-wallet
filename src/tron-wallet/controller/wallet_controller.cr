module Wallet
  module WalletController
    def wallet(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(login logout list create import delete address backup balance send claim)).not_nil!
      end

      generate_case("wallet", %w(login logout list create import delete address backup balance send claim))
    end

    def wallet_login(args)
      accounts = @wallet.db.get_accounts
      unless accounts.any?
        @wallet.prompt.say("No accounts yet. Create or import private key")
        return
      end
      
      account = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select account", accounts).not_nil!
      end

      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!

      encrypted = data[account]
      begin
        decrypted_data = @wallet.db.decrypt(encrypted, password)
        @wallet.account = account
        @wallet.address = decrypted_data["address"]
        @wallet.prompt.ok("Succesfully logged to #{account} (#{@wallet.address}) [ https://tronscan.org/#/address/#{@wallet.address} ]")
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end

    def wallet_logout(args)
      return unless authorized?

      @wallet.account = nil
      @wallet.address = nil
      @wallet.prompt.say("Logged out")
    end

    def wallet_list(args)
      accounts = @wallet.db.get_accounts
      @wallet.prompt.say("Available accounts:")
      accounts.each {|name| @wallet.prompt.say("• #{name}")}
    end

    def wallet_create(args)
      return unless connected?

      @wallet.prompt.warn("REMEMBER YOUR PASSWORD! YOU CAN'T RESTORE PRIVATE KEY WITHOUT IT!")
      name = if args.any?
        args.shift
      else
        @wallet.prompt.ask("Enter account name:", required: true)
      end
      
      exists = @wallet.db.get_account(name)
      if exists.any?
        @wallet.prompt.error("Account already exists")
        return
      end
      
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      password_repeat = @wallet.prompt.mask("Confirm password:", required: true)

      if password != password_repeat
        @wallet.prompt.error("Passwords not equal")
        return
      end

      result = @wallet.node.generate_address
      data = {"address" => result["address"].as_s, "key" => result["privateKey"].as_s}
      encrypted = @wallet.db.encrypt(data.to_json, password)

      @wallet.db.create_account(name, encrypted)
      @wallet.prompt.say("Account #{name} created! Your address - #{data["address"]}")
    end

    def wallet_import(args)
      @wallet.prompt.warn("REMEMBER YOUR PASSWORD! YOU CAN'T RESTORE PRIVATE KEY WITHOUT IT!")
      name = if args.any?
        args.shift
      else
        @wallet.prompt.ask("Enter account name:", required: true)
      end

      exists = @wallet.db.get_account(name)
      if exists.any?
        @wallet.prompt.error("Account already exists")
        return
      end

      address = if args.any?
        args.shift
      else
        @wallet.prompt.ask("Enter address:", required: true)
      end
      
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      password_repeat = @wallet.prompt.mask("Confirm password:", required: true)

      if password != password_repeat
        @wallet.prompt.error("Passwords not equal")
        return
      end

      private_key = @wallet.prompt.ask("Enter private key:", required: true)

      @wallet.prompt.say("\n")
      @wallet.prompt.say("Account: #{name}")
      @wallet.prompt.say("Address: #{address}")
      @wallet.prompt.say("Private key: #{private_key}")
      @wallet.prompt.say("\n")
      result = @wallet.prompt.no?("Import this account?")

      if result
        data = {"address" => address, "key" => private_key}
        encrypted = @wallet.db.encrypt(data.to_json, password)
        @wallet.db.create_account(name, encrypted)
        @wallet.prompt.say("Account #{name} created! Imported address - #{data["address"]}")
      else
        @wallet.prompt.say("Import canceled")
      end
    end

    def wallet_delete(args)
      return unless authorized?

      account = @wallet.account

      @wallet.prompt.error("ACCOUNT `#{account}` WILL BE DELETED!")
      result = @wallet.prompt.no?("Delete this account?")
      if result
        password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      
        data = @wallet.db.get_account(account)
        encrypted = data[account]
        begin
          @wallet.db.decrypt(encrypted, password)
          @wallet.db.delete_account(account)
          @wallet.account = nil
          @wallet.address = nil
          @wallet.prompt.ok("Account #{account} deleted!")
        rescue OpenSSL::Cipher::Error
          @wallet.prompt.error("Invalid password!")
        end
      else
        @wallet.prompt.say("Delete canceled")
      end
    end

    def wallet_address(args)
      unless args.any?
        return unless authorized?
        @wallet.prompt.say(@wallet.address)
        return
      end

      account = args.shift
      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      encrypted = data[account]
      begin
        decrypted_data = @wallet.db.decrypt(encrypted, password)
        address = decrypted_data["address"]
        @wallet.prompt.say(address)
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end

    def wallet_backup(args)
      account = if args.any?
        args.shift
      else
        return unless authorized?
        @wallet.account
      end
      
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      begin
        data = @wallet.db.decrypt(encrypted, password)
        address = data["address"]
        key = data["key"]
        @wallet.prompt.say("Address: #{address}")
        @wallet.prompt.say("Private key: #{key}")
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end

    def wallet_balance(args)
      return unless connected?

      account = if args.any?
        args.shift
      else
        return unless authorized?
        @wallet.account
      end

      address = if account == @wallet.account
        @wallet.address
      else
        get_account_address(account)
      end

      stats = @wallet.node.get_net_stats(address)
      @wallet.prompt.say("Bandwidth: #{stats["bandwidth_free"]}/#{stats["bandwidth_limit"]} Energy: #{stats["energy"]}")
      reward = @wallet.node.get_unclaimed_rewards(address)
      if reward > 0
        @wallet.prompt.say("Unclaimed rewards: #{reward} TRX")
      end

      # @wallet.prompt.say("Bandwidth: #{stats["bandwidth_free"]}/#{stats["bandwidth_limit"]} Energy: #{stats["energy"]}")
      balance_info = @wallet.node.get_balance(address)
    
      @wallet.prompt.say("TRX: #{balance_info["balance"]}. Frozen: #{balance_info["frozen"]} (E: #{balance_info["frozen_balance_for_energy"]} BW: #{balance_info["frozen_balance_for_bandwidth"]}) Votes: #{balance_info["votes"]}")
      contracts = @wallet.db.get_contracts
      contracts.each do |name, contract|
        @wallet.prompt.say("#{name}: #{@wallet.node.get_token_balance(address, contract)}")
      end
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    end

    
    
    def wallet_claim(args)
      return unless connected?
      return unless authorized?

      account = @wallet.account
      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      encrypted = data[account]
      begin
        password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
        decrypted_data = @wallet.db.decrypt(encrypted, password)
        private_key = decrypted_data["key"]
        @wallet.node.claim_rewards(@wallet.address.not_nil!, private_key)
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end

    def wallet_send(args)
      return unless connected?
      return unless authorized?
      contracts = @wallet.db.get_contracts
      accounts = @wallet.db.get_accounts
      book = @wallet.db.get_book

      address = case @wallet.prompt.select("Select method", ["Enter address", "Select from addressbook", "Select another account in the wallet"])
      when "Enter address"
        @wallet.prompt.ask("Address", required: true).not_nil!
      when "Select from addressbook"
        unless book.any?
          @wallet.prompt.warn("There is no records in the addressbook, use `book` command")
          return
        end

        @wallet.prompt.select("Select record") do |menu|
          book.each do |k, v|
            menu.choice "#{k} (#{v})", v
          end
        end
      when "Select another account in the wallet"
        if accounts.size == 1
          @wallet.prompt.warn("There is only one account it the wallet!")
          return
        end

        account = @wallet.prompt.select("Select account", accounts - [@wallet.account])
        get_account_address(account)
      end

      coin = @wallet.prompt.select("Select coin", ["TRX"] + contracts.keys).not_nil!

      coin == "TRX" ? wallet_send_trx(address.not_nil!) : wallet_send_token(address.not_nil!, coin, contracts)
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    end

    def wallet_send_trx(to_address : String)
      @wallet.prompt.say("Balance: #{@wallet.node.get_balance(@wallet.address)["balance"]}")
      amount = @wallet.prompt.ask("Enter amount:", required: true).not_nil!
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      account = @wallet.account
      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      encrypted = data[account]
      begin
        decrypted_data = @wallet.db.decrypt(encrypted, password)
        private_key = decrypted_data["key"]
        @wallet.prompt.warn("TRANSACTION INFO")
        @wallet.prompt.say("From: #{@wallet.address}")
        @wallet.prompt.say("To: #{to_address}")
        @wallet.prompt.say("Amount: #{amount} TRX")
        res = @wallet.prompt.no?("Confirm?")
        return unless res

        result, message, transaction_id = @wallet.node.transfer(address: to_address, private_key: private_key, amount: amount.to_f64)
        @wallet.prompt.say("\n")
        @wallet.prompt.say("Transaction ID: #{transaction_id}")
        @wallet.prompt.say("Details: https://tronscan.io/#/transaction/#{transaction_id}")
        if result == "OK"
          @wallet.prompt.ok("Transaction successfull!")
        else
          @wallet.prompt.error("Transaction failed: #{message}")
        end
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end


    def wallet_send_token(to_address : String, coin : String, contracts : Hash(String, String))
      contract = contracts[coin]
      @wallet.prompt.say("Balance: #{@wallet.node.get_token_balance(@wallet.address, contract)}")
      amount = @wallet.prompt.ask("Enter amount", required: true).not_nil!
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      account = @wallet.account
      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      encrypted = data[account]
      begin
        decrypted_data = @wallet.db.decrypt(encrypted, password)
        private_key = decrypted_data["key"]
        @wallet.prompt.warn("TRANSACTION INFO")
        @wallet.prompt.say("From: #{@wallet.address}")
        @wallet.prompt.say("To: #{to_address}")
        @wallet.prompt.say("Amount: #{amount} #{coin}")
        res = @wallet.prompt.no?("Confirm?")
        return unless res

        result, message, transaction_id = @wallet.node.transfer_token(
          address: to_address, private_key: private_key, contract: contract, amount: amount.to_f64
        )

        @wallet.prompt.say("\n")
        @wallet.prompt.say("Transaction ID: #{transaction_id}")
        @wallet.prompt.say("Details: https://tronscan.io/#/transaction/#{transaction_id}")
        if result == "OK"
          @wallet.prompt.ok("Transaction successfull!")
        else
          @wallet.prompt.error("Transaction failed: #{message}")
        end
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
      end
    end

    def wallet_rename(args)
      from, to = case {@wallet.account, args[0]?, args[1]?}
      when {_, String, String}
        {args[0], args[1]}
      when {String, String, nil}
        {
          @wallet.prompt.ask("Old name:", default: @wallet.account, required: true).not_nil!,
          @wallet.prompt.ask("New name:", default: args[0], required: true).not_nil!
        }
      when {String, nil, nil}
        {
          @wallet.prompt.ask("Old name:", default: @wallet.account, required: true).not_nil!,
          @wallet.prompt.ask("New name:", required: true).not_nil!
        }
      when {nil, String, nil}
        {
          @wallet.prompt.ask("Old name:", default: args[0], required: true).not_nil!,
          @wallet.prompt.ask("New name:", required: true).not_nil!
        }
      when {nil, nil, nil}
        {
          @wallet.prompt.ask("Old name:", required: true).not_nil!,
          @wallet.prompt.ask("New name:", required: true).not_nil!
        }
      else
        raise "Something went wrong!"
      end

      accounts = @wallet.db.get_accounts

      unless accounts.includes? from
        @wallet.prompt.error("There is no account named #{from}!")
        return
      end

      if accounts.includes? to
        @wallet.prompt.error("Account named #{to} already exists!")
        return
      end

      @wallet.db.rename_account(from, to)

      @wallet.prompt.ok("Account #{from} was renamed to #{to}!")

      if @wallet.account == from
        @wallet.account = to
      end
    end

    def get_account_address(account)
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      data = @wallet.db.decrypt(encrypted, password)
      data["address"]
    end
  end
end