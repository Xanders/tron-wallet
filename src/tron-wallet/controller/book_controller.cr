module Wallet
  module BookController
    def book(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(list create delete)).not_nil!
      end

      generate_case("book", %w(list create delete))
    end

    def book_list(args)
      book = @wallet.db.get_book
      unless book.any?
        @wallet.prompt.say("No records yet")
        return
      end

      book.each do |name, address|
        @wallet.prompt.say("• #{name} (#{address})")
      end
    end

    def book_create(args)
      book = @wallet.db.get_book
      name = @wallet.prompt.ask("Enter visible name:", required: true).not_nil!

      if book.keys.includes?(name)
        @wallet.prompt.say("Name `#{name}` already exists")
        return
      end

      address = @wallet.prompt.ask("Enter contract address:", required: true)

      if book.values.includes?(address)
        @wallet.prompt.say("Address #{address} already exists")
        return
      end

      res = @wallet.prompt.yes?("Create record `#{name}` (#{address})?")
      return unless res

      @wallet.db.add_book(name, address)
      @wallet.prompt.ok("Record `#{name}` created!")
    end

    def book_delete(args)
      book = @wallet.db.get_book

      name = @wallet.prompt.select("Select record") do |menu|
        book.each do |k, v|
          menu.choice "#{k} (#{v})", k
        end
      end

      unless book.keys.includes?(name)
        @wallet.prompt.say("Record `#{name}` not exists")
        return
      end

      address = book[name]
      res = @wallet.prompt.no?("Confirm delete record `#{name}` (#{address}) ?")
      return unless res

      @wallet.db.delete_book(name, address)
      @wallet.prompt.ok("Record #{name} (#{address}) removed!")
    end
  end
end