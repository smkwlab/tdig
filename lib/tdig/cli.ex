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
        ignore: :boolean,
        edns: :boolean,
        bufsize: :integer,
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
        e: :edns,
        b: :bufsize,
        h: :help,
        w: :write,
        r: :read,
        f: :read,
        v: :version,
      ])
    |> parse_switches
    |> parse_argv
    |> merge_switches_and_argv
    |> Map.put_new(:server, "8.8.8.8")
    |> Map.put_new(:v4, true)
    |> Map.put_new(:v6, false)
    |> Map.put_new(:port, 53)
    |> Map.put_new(:type, :a)
    |> Map.put_new(:class, :in)
    |> Map.put_new(:ignore, false)
    |> Map.put_new(:edns, false)
    |> Map.put_new(:read, nil)
    |> Map.put_new(:write, nil)
    |> Map.put_new(:write_request, nil)
    |> check_server_address
    |> check_edns
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

  def check_server_address(arg) do
    case arg.server |> String.to_charlist |> :inet.parse_address do
      {:ok, address} ->
        case tuple_size(address) do
          4 -> arg |> Map.put(:v4, true) |> Map.put(:v6, false)
          8 -> arg |> Map.put(:v4, false) |> Map.put(:v6, true)
        end
      _ ->
        arg
    end
  end

  def check_edns(%{bufsize: size} = arg) when is_integer(size), do: mk_edns(arg)
  def check_edns(%{edns: false} = arg), do: arg

  def check_edns(arg) do
    arg
    |> Map.put(:bufsize, DNS.edns_max_udpsize)
    |> mk_edns
  end

  def mk_edns(arg) do
    arg
    |> Map.put(:edns, true)
    |> Map.put(:ex_rcode, 0)
    |> Map.put(:options, [])
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

  def process(%{version: true}), do: IO.puts "tdig 0.1.1 (tenbin_dns 0.2.3)"
  
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
       --ignore               Don't revert to TCP for TC responses
    -e --edns                 use EDNS0
    -b --bufsize <size>       set EDNS0 Max UDP packet size
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

