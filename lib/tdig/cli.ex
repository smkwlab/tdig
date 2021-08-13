defmodule Tdig.CLI do
  require Logger

  @moduledoc """
  
  """

  def main(argv) do
    argv
    |> parse_args
    |> inspect
    |> Logger.debug
  end

  def parse_args(argv) do
    argv
    |> OptionParser.parse(
      strict: [
        class: :string,
        type: :string,
        query: :string,
        port: :integer,
        help: :boolean,
      ],
      aliases: [
        c: :class,
        t: :type,
        q: :query,
        p: :port,
        h: :help,
      ])
    |> parse_switches
    |> parse_argv
  end

  def parse_switches({parsed, argv, errors}) do
    {Enum.map(parsed, fn n -> switch_convert_atom(n) end), argv, errors}
  end

  def switch_convert_atom({:class, value}) do
    {:class, str2atom(value)}
  end

  def switch_convert_atom({:type, value}) do
    {:type, str2atom(value)}
  end

  def str2atom(arg) do
    String.to_atom(String.downcase(arg))
  end

  def parse_argv({parsed, argv, errors}) do
    {parsed, parse_argv_item(argv, %{server: nil, name: nil, type: nil, class: nil}), errors}
  end

  def parse_argv_item([], result) do
    result
  end

  def parse_argv_item([<<"@",arg1::binary>> | argv], result) do
    parse_argv_item(argv, %{result | server: arg1})
  end

  def parse_argv_item([arg1 | argv], %{name: nil} = result) do
    parse_argv_item(argv, %{result | name: arg1})
  end

  def parse_argv_item([arg1 | argv], %{type: nil} = result) do
    parse_argv_item(argv, %{result | type: str2atom(arg1)})
  end

  def parse_argv_item([arg1 | argv], %{class: nil} = result) do
    parse_argv_item(argv, %{result | class: str2atom(arg1)})
  end

  def parse_argv_item(_, _) do
    IO.puts :stderr, "argument error"
    System.halt(1)
  end
end

