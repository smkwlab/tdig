defmodule Tdig.CLI do
  require Logger

  @moduledoc """
  
  """

  def main(argv) do
    argv
    |> parse_args
    |> process
  end

  def parse_args(argv) do
    argv
    |> OptionParser.parse(
      strict: [
        class: :string,
        type: :string,
        port: :integer,
        v4: :boolean,
        v6: :boolean,
        help: :boolean,
      ],
      aliases: [
        c: :class,
        t: :type,
        p: :port,
        h: :help,
      ])
    |> parse_switches
    |> parse_argv
    |> merge_switches_and_argv
    |> add_default(:server, "8.8.8.8")
    |> add_default(:v4, true)
    |> add_default(:v6, false)
    |> add_default(:port, 53)
    |> add_default(:type, :a)
    |> add_default(:class, :in)
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

  def switch_convert_atom(n) do
    n
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
    argv |> parse_argv_item(%{result | name: arg1 |> add_tail_dot})
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

  def add_tail_dot(name) do
    if name |> String.ends_with?(".") do
      name
    else
      name <> "."
    end
  end

  def merge_switches_and_argv({parsed, argv, _errors}) do
    switch_to_arg(parsed, argv)
  end

  def switch_to_arg([], result) do
    result
  end
    
  def switch_to_arg([{k, v} | list], result) do
    switch_to_arg(list,  Map.put(result, k, v))
  end

  def add_default(arg, key, value) do
    add_default_item(arg, arg[key], key, value)
  end

  def add_default_item(arg, nil, key, value) do
    arg
    |> Map.put(key, value)
  end

  def add_default_item(arg, _, _, _) do
    arg
  end

  def process(%{help: true}) do
    IO.puts """
Usage: tdig [options] [@server] host [type] [class]
  -
"""
    System.halt(0)
  end

  def process(arg) do
    arg
    |> Tdig.resolve
  end

end

