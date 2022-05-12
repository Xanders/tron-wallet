module Wallet
  module WitnessController
    def witness(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(list vote)).not_nil!
      end

      generate_case("witness", %w(list vote))
    end

    def witness_list(args)
      return unless connected?

      @wallet.prompt.say("\nAddress#{" " * 27} | Number of votes\t| URL or title")

      WitnessController.list(@wallet.node).each do |witness|
        @wallet.prompt.say("#{witness["address"]} | #{witness["voteCount"].format('.', ' ')}\t| #{witness["url"].strip}")
      end
    end

    def witness_vote(args)
      return unless connected?
      return unless authorized?

      balance = @wallet.node.get_trx_balance(@wallet.address.not_nil!)
      tron_power = balance["tron_power"]
      if tron_power.zero?
        @wallet.prompt.warn("You have no votes! Use `stake` command to obtain some.")
        return
      end

      top = WitnessController.top(@wallet.node)
      choices = top.map do |witness|
        {
          name: "#{witness["url"]} (votes: #{witness["voteCount"].format('.', ' ')})",
          value: witness["address"]
        }
      end
      choices.push({
        name: "Non-SR address (use `witness list` to view all of them)",
        value: "ADDRESS"
      })
      choices.push({
        name: "Fair random",
        value: "RANDOM"
      })

      # Do not use `enum_select` since it's broken!
      witness = @wallet.prompt.select("Select the witness (only SR nodes shown):", choices, default: choices.size, page_size: 30, required: true).not_nil!
      case witness
      when "ADDRESS"
        witness = @wallet.prompt.ask("Enter address:", required: true).not_nil!
      when "RANDOM"
        witness = top.sample["address"]
      end

      @wallet.prompt.warn("Note: Multivoting is not supported by this wallet!")

      votes_used = balance["votes_used"]
      if votes_used.zero?
        @wallet.prompt.warn("It's recommended to use all the votes at once. You can re-vote at any time.")
      else
        @wallet.prompt.warn("All you previous votings will be REPLACED with this one!")
      end

      @wallet.prompt.say("You have #{tron_power} votes you can use")
      votes = @wallet.prompt.ask("Number of votes:", default: tron_power.to_s, required: true).not_nil!.to_i32
      private_key = get_logged_account_key

      show_transaction_result(*@wallet.node.vote_for_witness(
        address: @wallet.address.not_nil!,
        witness: witness,
        votes: votes,
        private_key: private_key
      ))
    rescue OpenSSL::Cipher::Error
      @wallet.prompt.error("Invalid password!")
    rescue Wallet::Node::RequestError
      @wallet.prompt.error("\nDANGER: Result is unpredictable, double check your state before continue!")
    end

    def self.list(node)
      node.get_witnesses_list["witnesses"].as_a.map do |element|
        {
          "address": TronAddress.to_base58(element["address"].as_s),
          "url": element["url"].as_s,
          "voteCount": element["voteCount"]? ? element["voteCount"].as_i : 0
        }
      end.sort_by(&.[]("voteCount")).reverse
    end

    def self.top(node)
      list(node)[0...27]
    end
  end
end