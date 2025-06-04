[
  # Ignore Bakeware.Script behaviour issues since we can't control that dependency
  ~r/deps\/bakeware/,
  ~r/Callback info about the Bakeware.Script behaviour is not available/,
  ~r/Function _main\/0 has no local return/,
  # Ignore Application behaviour warnings from Elixir itself
  ~r/lib\/elixir\/lib\/application.ex/
]