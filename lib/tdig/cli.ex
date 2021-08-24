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
        ptr: :boolean,
        tcp: :boolean,
        v4: :boolean,
        v6: :boolean,
        help: :boolean,
        write: :string,
        write_request: :string,
        read: :string,
        version: :boolean,
      ],
      aliases: [
        c: :class,
        t: :type,
        p: :port,
        x: :ptr,
        h: :help,
        w: :write,
        r: :read,
        f: :read,
        v: :version,
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
    |> add_default(:read, nil)
    |> add_default(:write, nil)
    |> add_default(:write_request, nil)
    |> check_args
 end

  def parse_switches({parsed, argv, errors}),
    do: {Enum.map(parsed, &(switch_convert_atom(&1))), argv, errors}

  def switch_convert_atom({:class, value}), do: {:class, str2atom(value)}
  def switch_convert_atom({:type, value}), do: {:type, str2atom(value)}
  def switch_convert_atom(n), do: n

  def str2atom(arg), do: arg |> String.downcase |> String.to_atom

  def parse_argv({parsed, argv, errors}) do
    {parsed, argv |> parse_argv_item(%{server: nil, name: nil, type: nil, class: nil}), errors}
  end

  def parse_argv_item([], result) do
    result
  end

  def parse_argv_item([<<"@",arg1::binary>> | argv], result) do
    argv |> parse_argv_item(%{result | server: arg1})
  end

  def parse_argv_item([arg1 | argv], %{name: nil} = result) do
    argv |> parse_argv_item(%{result | name: arg1 |> add_tail_dot})
  end

  def parse_argv_item([arg1 | argv], %{type: nil} = result) do
    argv |> parse_argv_item(%{result | type: arg1 |> str2atom})
  end

  def parse_argv_item([arg1 | argv], %{class: nil} = result) do
    argv |> parse_argv_item(%{result | class: arg1 |> str2atom})
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

  def switch_to_arg([], result), do: result
  def switch_to_arg([{k, v} | list], result), do: switch_to_arg(list,  result |> Map.put(k, v))

  def add_default(arg, key, value), do: add_default_item(arg, arg[key], key, value)

  def add_default_item(arg, nil, key, value), do: Map.put(arg, key, value)
  def add_default_item(arg, _, _, _), do: arg

  end

  def check_args(%{help: true}), do: %{help: true, exit_code: 0}
  def check_args(%{name: nil, read: nil, version: nil}), do: %{help: true, exit_code: 1}

  def check_args(%{ptr: true} = args) do
    args
    |> Map.put(:name, (args[:name] |> String.split(".") |> Enum.reverse |> tl |> Enum.join(".")) <> ".in-addr.arpa.")
    |> Map.put(:type, :ptr)
  end
      
  def check_args(arg) do
    arg
  end

  def process(%{version: true}), do: IO.puts "tdig 0.1.0 (tenbin_dns 0.2.1)"
  
  def process(%{help: true, exit_code: exit_code}) do
    IO.puts """
    Usage: tdig [options] [@server] host [type] [class]
    
    options
    -c --class <class>        specify query class
    -t --type <type>          specify query type
    -p --port <port>          specify port number
    -x --ptr                  shortcut for reverse lookup
       --v4                   use IPv4 transport
       --v6                   use IPv6 transport
       --tcp                  TCP mode
    -r --read <file>          read packet from file
    -f        <file>          same as -r
    -w --write <file>         write answer packet to file
       --write-request <file> write request packet to file
    -v --version              print version and exit
    -h --help                 print help and exit
    """
    System.halt(exit_code)
  end

  def process(arg) do
    arg
    |> Tdig.resolve
  end

end

