module Wallet
  module WalletController
    WALLET_COMMANDS = %w(login logout list create import delete address history backup balance send stake unstake unstake_v1 withdraw claim rename change_password)

    def wallet(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command:", WALLET_COMMANDS).not_nil!
      end

      generate_case("wallet", WALLET_COMMANDS)
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

      encrypted = data[account]
      decrypted_data = @wallet.db.decrypt(encrypted, ask_for_password)
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
      
      password = ask_for_password
      password_repeat = ask_for_password("Confirm password:")

      if password != password_repeat
        @wallet.prompt.error("Passwords are not equal!")
        return
      end

      address, private_key = @wallet.node.generate_address
      data = {"address" => address, "key" => private_key}
      encrypted = @wallet.db.encrypt(data.to_json, password)

      @wallet.db.create_account(name, encrypted)
      @wallet.prompt.ok("Account #{name} created! Your address - #{address}")
      @wallet.prompt.say("Do not forget to fill it with some TRX for activation and fees before sending any tokens")
      @wallet.prompt.warn("\nWARNING: There is no guarantee the private-key-to-address algorithm used in this wallet is matching current Tron version! Please test outgoing transaction from this wallet with small TRX amount BEFORE sending big amount of TRX or tokens here!\n")
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
      
      password = ask_for_password
      password_repeat = ask_for_password("Confirm password:")

      if password != password_repeat
        @wallet.prompt.error("Passwords are not equal!")
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

      data = @wallet.db.get_account(account)
      encrypted = data[account]
      @wallet.db.decrypt(encrypted, ask_for_password)
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

      encrypted = data[account]
      decrypted_data = @wallet.db.decrypt(encrypted, ask_for_password)
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
      @wallet.prompt.say("\nNote #1: for token transfers click on transaction hash to see the sum", color: :dark_grey)
      @wallet.prompt.say("\nNote #2: if you are on testnet, use another domain, for example shasta.tronscan.org", color: :dark_grey)
    end

    def wallet_backup(args)
      account = if args.any?
        args.shift
      else
        return unless authorized?
        @wallet.account
      end
      
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      data = @wallet.db.decrypt(encrypted, ask_for_password)
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
        @wallet.prompt.say("Unclaimed rewards: #{reward} TRX, use `claim` command to obtain it")
      end

      balance_info = @wallet.node.get_trx_balance(address)
      @wallet.prompt.say("TRX: #{balance_info[:balance].format}. Staked: #{balance_info[:frozen]} (E: #{balance_info[:frozen_balance_for_energy]}, BW: #{balance_info[:frozen_balance_for_bandwidth]}). Votes used: #{balance_info[:votes_used]}/#{balance_info[:tron_power]}")

      withdrawable = @wallet.node.get_withdrawable_balance(address)
      if withdrawable > 0
        @wallet.prompt.warn("Your #{withdrawable} TRX was fully unstaked, you now able to `withdraw` it to your balance!")
      end

      if balance_info[:frozen_v1] > 0
        @wallet.prompt.warn("Deprecated Stake 1.0 found! #{balance_info[:frozen_v1]} TRX (E: #{balance_info[:frozen_v1_balance_for_energy]}, BW: #{balance_info[:frozen_v1_balance_for_bandwidth]}). Use `unstake_v1` command and `stake` again for Stake 2.0 version.")
      end

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

      @wallet.prompt.warn("\nWARNING: At the moment of implementing, unstake time for Stake 2.0 system is 14 days! You will not be able to use your TRX for two weeks after unstake!\nAlso, number of unstakes per account is limited to 32.")
      confirm = @wallet.prompt.yes?("Is it OK for you?")
      return unless confirm

      balance = @wallet.node.get_trx_balance(@wallet.address)[:balance]
      @wallet.prompt.say("\nBalance: #{balance.format}")
      input = @wallet.prompt.ask("Enter amount:", default: "all", required: true).not_nil!
      amount = input == "all" ? balance : input.to_f64

      private_key = get_logged_account_key

      resource = @wallet.prompt.select("Which resource you want to gain?", ["ENERGY", "BANDWIDTH"]).not_nil!

      @wallet.prompt.warn("\nSTAKE INFO")
      @wallet.prompt.say("Owner: #{@wallet.address} (#{@wallet.account})")
      @wallet.prompt.say("Amount: #{amount} TRX")
      @wallet.prompt.say("Resource to gain: #{resource}")

      confirm = @wallet.prompt.yes?("Confirm?")
      return unless confirm

      result, message, transaction_id = @wallet.node.stake(
        address: @wallet.address.not_nil!,
        amount: amount,
        resource: resource,
        private_key: private_key
      )

      show_transaction_result(result, message, transaction_id)

      return unless result == "OK"

      want_to_vote = @wallet.prompt.yes?("\nDo you want to vote for best-by-your-profit SR-node with all staked TRX for additional rewards?")
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
      for_energy, for_bandwidth = balance_info[:frozen_balance_for_energy], balance_info[:frozen_balance_for_bandwidth]
      resources = case {for_energy, for_bandwidth}
      when {.zero?, .zero?}
        @wallet.prompt.warn("There is no staked TRX on #{@wallet.account} account!")
        return
      when {.zero?, _}
        @wallet.prompt.say("Staked TRX: #{for_bandwidth} for bandwidth")
        ["BANDWIDTH"]
      when {_, .zero?}
        @wallet.prompt.say("Staked TRX: #{for_energy} for energy")
        ["ENERGY"]
      else
        @wallet.prompt.say("Staked TRX: #{balance_info[:frozen]} total; for energy: #{for_energy}, for bandwidth: #{for_bandwidth}")
        answer = @wallet.prompt.select("Which stake you want to release?", ["BOTH", "ENERGY", "BANDWIDTH"]).not_nil!
        if answer == "BOTH"
          ["ENERGY", "BANDWIDTH"]
        else
          [answer]
        end
      end

      private_key = get_logged_account_key

      resources.each do |resource|
        @wallet.prompt.say("\nFor #{resource}:") if resources.size > 1

        balance = {"ENERGY" => for_energy, "BANDWIDTH" => for_bandwidth}[resource]
        input = @wallet.prompt.ask("Enter amount:", default: "all", required: true).not_nil!
        amount = input == "all" ? balance : input.to_f64

        @wallet.prompt.warn("\nUNSTAKE INFO")
        @wallet.prompt.say("Owner: #{@wallet.address} (#{@wallet.account})")
        @wallet.prompt.say("Resource to release: #{resource}")
        @wallet.prompt.say("Amount: #{amount} TRX")

        confirm = @wallet.prompt.yes?("Confirm?")
        break unless confirm

        show_transaction_result(*@wallet.node.unstake(
          address: @wallet.address.not_nil!,
          amount: amount,
          resource: resource,
          private_key: private_key
        ))
      end

      @wallet.prompt.warn("Your TRX will be available in a two weeks (at the moment of implementing).\nBut unstaked TRX will not appended to your balance automatically, you'll need to `withdraw` them with corresponding command.")
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
    end

    def wallet_unstake_v1(args)
      return unless connected?
      return unless authorized?

      balance_info = @wallet.node.get_trx_balance(@wallet.address)
      for_energy, for_bandwidth = balance_info[:frozen_v1_balance_for_energy], balance_info[:frozen_v1_balance_for_bandwidth]
      resources = case {for_energy, for_bandwidth}
      when {.zero?, .zero?}
        @wallet.prompt.warn("There is no staked TRX on #{@wallet.account} account!")
        return
      when {.zero?, _}
        @wallet.prompt.say("Staked TRX: #{for_bandwidth} for bandwidth")
        ["BANDWIDTH"]
      when {_, .zero?}
        @wallet.prompt.say("Staked TRX: #{for_energy} for energy")
        ["ENERGY"]
      else
        @wallet.prompt.say("Staked TRX: #{balance_info[:frozen]} total; for energy: #{for_energy}, for bandwidth: #{for_bandwidth}")
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

        show_transaction_result(*@wallet.node.unstake_v1(
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

    def wallet_withdraw(args)
      return unless connected?
      return unless authorized?
      show_transaction_result(*@wallet.node.withdraw_unstaked_trx(@wallet.address.not_nil!, get_logged_account_key))
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
      if one_password_for_all_mode?
        @wallet.prompt.error("You cannot change password when `TRON_WALLET_ONE_INSECURE_PASSWORD` environment variable is set!")
        return
      end

      account = if args.any?
        args.shift
      else
        return unless authorized?
        @wallet.account
      end

      old_password = ask_for_password("Old password:")
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      begin
        data = @wallet.db.decrypt(encrypted, old_password)
      rescue OpenSSL::Cipher::Error
        @wallet.prompt.error("Invalid password!")
        return
      end

      @wallet.prompt.warn("REMEMBER YOUR NEW PASSWORD! YOU CAN'T RESTORE PRIVATE KEY WITHOUT IT!")

      new_password = ask_for_password("New password:")
      new_password_repeat = ask_for_password("Confirm new password:")

      if new_password != new_password_repeat
        @wallet.prompt.error("Passwords are not equal!")
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
      data = @wallet.db.get_account(account)
      encrypted = data[account]
      decrypted = @wallet.db.decrypt(encrypted, ask_for_password)

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