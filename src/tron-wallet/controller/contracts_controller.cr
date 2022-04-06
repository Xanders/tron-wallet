module Wallet
  module ContractsController
    def contracts(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(list create delete)).not_nil!
      end

      generate_case("contracts", %w(list create delete))
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
  end
end