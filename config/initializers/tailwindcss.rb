Tailwindcss::Commands.singleton_class.prepend(Module.new do
  def compile_command(debug: false, **kwargs)
    super.tap do |command|
      idx = command.index("-i")
      command[idx + 1] = Rails.root.join("app/assets/tailwind/application.tailwind.css").to_s if idx
    end
  end
end)
