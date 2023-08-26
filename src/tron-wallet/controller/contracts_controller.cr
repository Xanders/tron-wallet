module Wallet
  module ContractsController
    CONTRACT_COMMANDS = %w(list create delete)

    def contracts(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command:", CONTRACT_COMMANDS).not_nil!
      end

      generate_case("contracts", CONTRACT_COMMANDS)
    end

    def contracts_list(args)
      contracts = @wallet.db.get_contracts
      unless contracts.any?
        @wallet.prompt.say("No contracts yet")
        return
      end

      contracts.each do |name, address|
        @wallet.prompt.say("• #{name.upcase} (#{address})")
      end
    end

    def contracts_create(args)
      return unless connected?

      contracts = @wallet.db.get_contracts

      name = if args.any?
        args.shift
      else
        @wallet.prompt.ask("Enter visible name:", required: true).not_nil!.upcase
      end

      if contracts.keys.includes?(name)
        @wallet.prompt.say("Name #{name} already exists")
        return
      end

      address = if args.any?
        args.shift
      else
        @wallet.prompt.ask("Enter contract address:", required: true)
      end

      if contracts.values.includes?(address)
        @wallet.prompt.say("Contract address #{address} already exists")
        return
      end

      contract_name = @wallet.node.get_contract_name(address)

      if contract_name
        @wallet.prompt.say("Finded contract name: #{contract_name}")
        res = @wallet.prompt.yes?("Continue?")
        return unless res
 
        @wallet.db.add_contract(name, address)
        @wallet.prompt.say("Added contract #{name} (#{address} | #{contract_name})")
      else
        @wallet.prompt.warn("Contract not found")
      end
    rescue Wallet::Node::RequestError
      # OK, it is safe
    end

    def contracts_delete(args)
      contracts = @wallet.db.get_contracts

      name = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select contract") do |menu|
          contracts.each do |k, v|
            menu.choice "#{k}: #{v}", k
          end
        end
      end

      unless contracts.keys.includes?(name)
        @wallet.prompt.say("Contract #{name} not exists")
        return
      end
      address = contracts[name]
      res = @wallet.prompt.no?("Confirm delete contract #{name} (#{address}) ?")
      return unless res

      @wallet.db.delete_contract(name, address)
      @wallet.prompt.ok("Contract #{name} (#{address}) removed!")
    end

    def fill_contracts_from_env!
      list = ENV["TRON_WALLET_PREDEFINED_CONTRACTS"]?
      return if list.nil? || list.empty?

      contracts = @wallet.db.get_contracts

      list.split(",").each do |pair|
        name, address = pair.strip.split(":", 2)

        if existing = contracts[name]?
          if existing == address
            next
          else
            raise "Contract with name #{name} already exists in DB and has address #{existing}, but environment variable address #{address} does not match! If you want to add mainnet and testnet contracts at same time, choose another name."
          end
        end

        contract_name = @wallet.node.get_contract_name(address)
        if contract_name
          @wallet.db.add_contract(name, address)
          @wallet.prompt.say("Added contract #{name} (#{address} | #{contract_name})")
        else
          raise "Contract #{name} with address #{address} from environment variable was not found in the Tron network! Double check you use mainnet or testnet."
        end
      end
    end
  end
end