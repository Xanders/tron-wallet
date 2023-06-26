module Wallet
  module WalletController
    def wallet(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(login logout list create import delete address history backup balance send stake unstake claim rename change_password)).not_nil!
      end

      generate_case("wallet", %w(login logout list create import delete address history backup balance send stake unstake claim rename change_password))
    end

    def wallet_login(args)
      accounts = @wallet.db.get_accounts
      unless accounts.any?
        @wallet.prompt.say("No accounts yet. Create or import private key")
        return
      end
      
      account = if args.any?
        args.shift
      elsif accounts.size == 1
        accounts[0]
      else
        @wallet.prompt.select("Select account:", accounts).not_nil!
      end

      data = @wallet.db.get_account(account)

      unless data.any?
        @wallet.prompt.error("No data for account `#{account}`")
        return
      end

      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!

      encrypted = data[account]
      decrypted_data = @wallet.db.decrypt(encrypted, password)
      @wallet.account = account
      @wallet.address = decrypted_data["address"]
      @wallet.prompt.ok("Succesfully logged to #{account} (#{@wallet.address})")
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
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
      accounts.each {|name| @wallet.prompt.say("• #{name}" + (name == @wallet.account ? " ◀◀◀ logged in" : ""))}
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
      @wallet.prompt.ok("Account #{name} created! Your address - #{data["address"]}")
      @wallet.prompt.say("Do not forget to fill it with some TRX for activation and commissions before sending any tokens")
    rescue Wallet::Node::RequestError
      # OK, it is safe
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
      confirm = @wallet.prompt.no?("Import this account?")
      return unless confirm

      data = {"address" => address, "key" => private_key}
      encrypted = @wallet.db.encrypt(data.to_json, password)
      @wallet.db.create_account(name, encrypted)
      @wallet.prompt.say("Account #{name} created! Imported address - #{data["address"]}")
    end

    def wallet_delete(args)
      return unless authorized?

      account = @wallet.account

      @wallet.prompt.error("ACCOUNT `#{account}` WILL BE DELETED!")
      confirm = @wallet.prompt.no?("Delete this account?")
      return unless confirm

      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      @wallet.db.decrypt(encrypted, password)
      @wallet.db.delete_account(account)
      @wallet.account = nil
      @wallet.address = nil
      @wallet.prompt.ok("Account #{account} deleted!")
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
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
      decrypted_data = @wallet.db.decrypt(encrypted, password)
      address = decrypted_data["address"]
      @wallet.prompt.say(address)
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    end

    def wallet_history(args)
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

      @wallet.prompt.say("You can see your transactions history here (ctrl+click):")
      @wallet.prompt.say("\nhttps://tronscan.io/#/address/#{address}")
      @wallet.prompt.say("\nNote: for token transfers click on transaction hash to see the sum")
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
      data = @wallet.db.decrypt(encrypted, password)
      address = data["address"]
      key = data["key"]
      @wallet.prompt.say("Address: #{address}")
      @wallet.prompt.say("Private key: #{key}")
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
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
      @wallet.prompt.say("Bandwidth: #{stats["bandwidth_free"]}/#{stats["bandwidth_limit"]}. Energy: #{stats["energy_free"]}/#{stats["energy_limit"]}")
      reward = @wallet.node.get_unclaimed_rewards(address)
      if reward > 0
        @wallet.prompt.say("Unclaimed rewards: #{reward} TRX")
      end

      balance_info = @wallet.node.get_trx_balance(address)
      @wallet.prompt.say("TRX: #{balance_info[:balance].format}. Staked: #{balance_info[:frozen]} (E: #{balance_info[:frozen_balance_for_energy]}, BW: #{balance_info[:frozen_balance_for_bandwidth]}). Votes used: #{balance_info[:votes_used]}/#{balance_info[:tron_power]}")

      contracts = @wallet.db.get_contracts
      contracts.each do |name, contract|
        @wallet.prompt.say("#{name}: #{@wallet.node.get_token_balance(address, contract).format}")
      end
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      # OK, it is safe
    end

    def wallet_send(args)
      return unless connected?
      return unless authorized?
      contracts = @wallet.db.get_contracts

      address = case @wallet.prompt.select("Select method:", ["Enter address", "Select from addressbook", "Select another account in the wallet"])
      when "Enter address"
        @wallet.prompt.ask("Address:", required: true)
      when "Select from addressbook"
        select_account_from_the_book
      when "Select another account in the wallet"
        select_another_account_in_the_wallet
      end
      return unless address

      coin = @wallet.prompt.select("Select coin:", ["TRX"] + contracts.keys).not_nil!

      balance = if coin == "TRX"
        @wallet.node.get_trx_balance(@wallet.address)[:balance]
      else
        @wallet.node.get_token_balance(@wallet.address, contracts[coin])
      end

      @wallet.prompt.say("Balance: #{balance.format}")
      input = @wallet.prompt.ask("Enter amount or `all`:", required: true).not_nil!
      amount = input == "all" ? balance : input.to_f64

      private_key = get_logged_account_key

      @wallet.prompt.warn("\nTRANSACTION INFO")
      @wallet.prompt.say("From: #{@wallet.address} (#{@wallet.account})")
      @wallet.prompt.say("To: #{address}")
      @wallet.prompt.say("Amount: #{amount} #{coin}")

      result = if coin == "TRX"
        wallet_send_trx(amount, address.not_nil!, private_key)
      else
        wallet_send_token(amount, address.not_nil!, contracts[coin], private_key)
      end

      show_transaction_result(*result) if result
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
    end

    def wallet_send_trx(amount, address, private_key)
      @wallet.prompt.say("Fee: few bandwidth")
      confirm = @wallet.prompt.no?("Confirm?")
      return unless confirm

      @wallet.node.transfer_trx(
        amount: amount,
        address: address,
        private_key: private_key
      )
    end

    def wallet_send_token(amount, address, contract, private_key)
      estimate = @wallet.node.prepare_token_transfer(
        amount: amount,
        address: address,
        contract: contract,
        estimate_fee: true
      )

      if estimate["transaction"]?.nil? || estimate["energy_used"]?.nil?
        return "FAILED", estimate.to_json, nil
      end

      energy_fee = estimate["energy_used"].as_i64
      energy_price = @wallet.node.get_energy_price
      bandwidth_fee = estimate["transaction"]["raw_data_hex"].as_s.bytesize
      bandwidth_price = @wallet.node.get_bandwidth_price

      @wallet.prompt.say("Fee: ≈#{energy_fee} energy (≈#{(energy_fee * energy_price).format(decimal_places: 1)} TRX) and ≈#{bandwidth_fee} bandwidth (≈#{(bandwidth_fee * bandwidth_price).format(decimal_places: 1)} TRX) bandwidth")
      confirm = @wallet.prompt.no?("Confirm?")
      return unless confirm

      transfer = @wallet.node.prepare_token_transfer(
        amount: amount,
        address: address,
        contract: contract
      )

      @wallet.node.sign_and_send(transfer["transaction"], private_key)
    end

    def wallet_stake(args)
      return unless connected?
      return unless authorized?

      @wallet.prompt.say("Balance: #{@wallet.node.get_trx_balance(@wallet.address)[:balance].format}")
      amount = @wallet.prompt.ask("Enter amount:", required: true).not_nil!.to_f64
      private_key = get_logged_account_key
      duration = @wallet.prompt.ask("Enter duration in days (minimum 3):", default: "3", required: true).not_nil!.to_i32
      resource = @wallet.prompt.select("Which resource you want to gain?", ["ENERGY", "BANDWIDTH"]).not_nil!
      receiver = case @wallet.prompt.select("Which account will recieve the resource?", ["This account", "Another account in the wallet", "Account from addressbook", "Enter address"])
      when "This account"
        @wallet.address
      when "Another account in the wallet"
        select_another_account_in_the_wallet
      when "Account from addressbook"
        select_account_from_the_book
      when "Enter address"
        @wallet.prompt.ask("Address", required: true)
      end
      return unless receiver

      @wallet.prompt.warn("\nSTAKE INFO")
      @wallet.prompt.say("Owner: #{@wallet.address} (#{@wallet.account})")
      @wallet.prompt.say("Amount: #{amount} TRX")
      @wallet.prompt.say("Duration: #{duration} days")
      @wallet.prompt.say("Resource to gain: #{resource}")
      @wallet.prompt.say("Receiver: #{receiver}")

      confirm = @wallet.prompt.no?("Confirm?")
      return unless confirm

      show_transaction_result(*@wallet.node.stake(
        address: @wallet.address.not_nil!,
        amount: amount,
        duration: duration,
        resource: resource,
        receiver: receiver,
        private_key: private_key
      ))

      want_to_vote = @wallet.prompt.yes?("Do you want to vote for best-by-your-profit SR-node with all staked TRX for additional rewards?")
      if want_to_vote
        tron_power = @wallet.node.get_trx_balance(@wallet.address.not_nil!)[:tron_power].as(Int32)

        @wallet.prompt.say("Loading brokerages to calculate your profit...")
        witness = WitnessController.top(@wallet.node)[0]["address"]

        show_transaction_result(*@wallet.node.vote_for_witness(
          address: @wallet.address.not_nil!,
          witness: witness,
          votes: tron_power,
          private_key: private_key
        ))
      end
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
    end

    def wallet_unstake(args)
      return unless connected?
      return unless authorized?

      balance_info = @wallet.node.get_trx_balance(@wallet.address)
      resources = case {balance_info[:frozen_balance_for_energy], balance_info[:frozen_balance_for_bandwidth]}
      when {.zero?, .zero?}
        @wallet.prompt.warn("There is no staked TRX on #{@wallet.account} account!")
        return
      when {.zero?, _}
        @wallet.prompt.say("Staked TRX: #{balance_info[:frozen_balance_for_bandwidth]} for bandwidth")
        ["BANDWIDTH"]
      when {_, .zero?}
        @wallet.prompt.say("Staked TRX: #{balance_info[:frozen_balance_for_energy]} for energy")
        ["ENERGY"]
      else
        @wallet.prompt.say("Staked TRX: #{balance_info[:frozen]} total; for energy: #{balance_info[:frozen_balance_for_energy]}, for bandwidth: #{balance_info[:frozen_balance_for_bandwidth]}")
        answer = @wallet.prompt.select("Which stake you want to release?", ["BOTH", "ENERGY", "BANDWIDTH"]).not_nil!
        if answer == "BOTH"
          ["ENERGY", "BANDWIDTH"]
        else
          [answer]
        end
      end

      private_key = get_logged_account_key

      receiver = case @wallet.prompt.select("Which account was used to gain the resource for stake?", ["This account", "Another account in the wallet", "Account from addressbook", "Enter address"])
      when "This account"
        @wallet.address
      when "Another account in the wallet"
        select_another_account_in_the_wallet
      when "Account from addressbook"
        select_account_from_the_book
      when "Enter address"
        @wallet.prompt.ask("Address", required: true)
      end
      return unless receiver

      @wallet.prompt.warn("\nUNSTAKE INFO")
      @wallet.prompt.say("Owner: #{@wallet.address} (#{@wallet.account})")
      @wallet.prompt.say("Resource to release: #{resources.join ", "}")
      @wallet.prompt.say("Source: #{receiver}")

      confirm = @wallet.prompt.no?("Confirm?")
      return unless confirm

      resources.each do |resource|
        @wallet.prompt.say("\nFor #{resource}:") if resources.size > 1

        show_transaction_result(*@wallet.node.unstake(
          address: @wallet.address.not_nil!,
          resource: resource,
          receiver: receiver,
          private_key: private_key
        ))
      end
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
    end

    def wallet_claim(args)
      return unless connected?
      return unless authorized?
      show_transaction_result(*@wallet.node.claim_rewards(@wallet.address.not_nil!, get_logged_account_key))
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
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

    def wallet_change_password(args)
      account = if args.any?
        args.shift
      else
        return unless authorized?
        @wallet.account
      end

      old_password = @wallet.prompt.mask("Old password:", required: true).not_nil!
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      begin
        data = @wallet.db.decrypt(encrypted, old_password)
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
        return
      end

      @wallet.prompt.warn("REMEMBER YOUR NEW PASSWORD! YOU CAN'T RESTORE PRIVATE KEY WITHOUT IT!")

      new_password = @wallet.prompt.mask("New password:", required: true).not_nil!
      new_password_repeat = @wallet.prompt.mask("Confirm new password:", required: true).not_nil!

      if new_password != new_password_repeat
        @wallet.prompt.error("Passwords not equal")
        return
      end

      encrypted = @wallet.db.encrypt(data.to_json, new_password)

      @wallet.db.update_account(account, encrypted)
      @wallet.prompt.ok("Password for account #{account} was changed!")
    end

    def get_account_address(account)
      get_account_data(account, "address")
    end

    def get_logged_account_key
      get_account_data(@wallet.account, "key")
    end

    def get_account_data(account, key)
      password = @wallet.prompt.mask("Enter password:", required: true).not_nil!
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      decrypted = @wallet.db.decrypt(encrypted, password)

      return decrypted[key]
    end

    def show_transaction_result(result, message, transaction_id)
      if transaction_id
        @wallet.prompt.say("\nTransaction ID: #{transaction_id}")
        @wallet.prompt.say("Details (ctrl+click):")
        @wallet.prompt.say("\nhttps://tronscan.io/#/transaction/#{transaction_id}")
      end

      if result == "OK"
        @wallet.prompt.ok("\nTransaction successfull!")
      else
        @wallet.prompt.error("\nTransaction failed!")
      end

      @wallet.prompt.say('\n' + message) unless message == ""
    end

    def select_account_from_the_book
      book = @wallet.db.get_book

      if book.empty?
        @wallet.prompt.warn("There is no records in the addressbook, use `book` command")
        return
      end

      @wallet.prompt.select("Select record") do |menu|
        book.each do |k, v|
          menu.choice "#{k} (#{v})", v
        end
      end
    end

    def select_another_account_in_the_wallet
      accounts = @wallet.db.get_accounts

      if accounts.size == 1
        @wallet.prompt.warn("There is only one account it the wallet!")
        return
      end

      account = @wallet.prompt.select("Select account", accounts - [@wallet.account])
      get_account_address(account)
    end
  end
end