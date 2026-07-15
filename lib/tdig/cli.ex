defmodule Tdig.CLI do
  use Bakeware.Script

  @moduledoc """
  Command-line interface for the Tdig DNS lookup utility.

  Supports both escript and Bakeware execution modes.
  Handles argument parsing, option processing, and main application entry point.
  """

  # Read the project version from mix.exs at compile time so `tdig --version`
  # never drifts from the canonical source (see Issue #49).
  @version Mix.Project.config()[:version]

  @doc """
  Returns the application version as defined in `mix.exs`.
  """
  @spec version() :: String.t()
  def version, do: @version

  # Entry point for both escript and Bakeware
  @impl Bakeware.Script
  @spec main([String.t()]) :: :ok
  def main(argv) do
    run(argv)
  end

  # Common execution logic for both modes
  defp run(argv) do
    argv
    |> parse_args()
    |> process()
  end

  @spec parse_args([String.t()]) :: map()
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
        sort: :boolean,
        help: :boolean,
        write: :string,
        write_request: :string,
        read: :string,
        version: :boolean,
        subnet: :string
      ],
      aliases: [
        c: :class,
        t: :type,
        p: :port,
        x: :ptr,
        e: :edns,
        b: :bufsize,
        s: :sort,
        h: :help,
        w: :write,
        r: :read,
        f: :read,
        v: :version
      ]
    )
    |> parse_switches
    |> parse_argv
    |> merge_switches_and_argv
    |> Map.update(:server, nil, fn n -> n || "8.8.8.8" end)
    |> Map.update(:type, nil, fn n -> n || :a end)
    |> Map.update(:class, nil, fn n -> n || :in end)
    |> Map.put_new(:v4, true)
    |> Map.put_new(:v6, false)
    |> Map.put_new(:port, 53)
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
    do: {Enum.map(parsed, &switch_convert_atom(&1)), argv, errors}

  def switch_convert_atom({:class, value}) do
    case parse_class(value) do
      nil -> invalid_argument("Unknown class: #{value}")
      class -> {:class, class}
    end
  end

  def switch_convert_atom({:type, value}) do
    case parse_type(value) do
      nil -> invalid_argument("Unknown type: #{value}")
      type -> {:type, type}
    end
  end

  def switch_convert_atom(n), do: n

  # Known RR type/class names derived from tenbin_dns at compile time
  # (classes are 16-bit, hence 0..0xFFFF). Runtime lookups are then pure
  # map reads: arbitrary input never creates atoms, and no module-load
  # order is assumed (escript loads modules lazily), see Issue #77.
  @type_by_name for code <- 0..0xFFFF,
                    type = DNS.type(code),
                    into: %{},
                    do: {Atom.to_string(type), type}

  @class_by_name for code <- 0..0xFFFF,
                     class = DNS.class(code),
                     into: %{},
                     do: {Atom.to_string(class), class}

  @doc """
  Converts a string to a known RR type atom, or returns `nil` so that
  an invalid type never reaches packet creation (Issue #77).
  """
  @spec parse_type(String.t()) :: atom() | nil
  def parse_type(arg), do: Map.get(@type_by_name, String.downcase(arg))

  @doc """
  Converts a string to a known DNS class atom, or returns `nil`.
  """
  @spec parse_class(String.t()) :: atom() | nil
  def parse_class(arg), do: Map.get(@class_by_name, String.downcase(arg))

  @spec invalid_argument(String.t()) :: no_return()
  defp invalid_argument(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end

  def parse_argv({parsed, argv, errors}) do
    {parsed, argv |> parse_argv_item(%{server: nil, name: nil, type: nil, class: nil}), errors}
  end

  def parse_argv_item([], %{name: nil} = result) do
    parse_argv_item([], %{result | name: "."})
  end

  def parse_argv_item([], result) do
    result
  end

  def parse_argv_item([<<"@", arg1::binary>> | argv], result) do
    parse_argv_item(argv, %{result | server: arg1})
  end

  def parse_argv_item([arg1 | argv], result) do
    parse_argv_item(argv, assign_positional_arg(arg1, result))
  end

  # dig-compatible positional argument handling (Issue #77): a token that
  # matches a known RR type (or class) name is taken as the type (or class)
  # regardless of position, so both `tdig txt sony.com` and
  # `tdig sony.com txt` work. Type wins over class for ambiguous tokens
  # such as "any", and a trailing dot (e.g. "txt.") forces a token to be
  # interpreted as a name, both as in dig.
  defp assign_positional_arg(arg, result) do
    type = if result.type == nil, do: parse_type(arg)
    class = if result.class == nil, do: parse_class(arg)

    cond do
      type -> %{result | type: type}
      class -> %{result | class: class}
      result.name == nil -> %{result | name: add_tail_dot(arg)}
      true -> invalid_argument("Invalid argument: #{arg}")
    end
  end

  @spec add_tail_dot(String.t()) :: String.t()
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
  def switch_to_arg([{k, v} | list], result), do: switch_to_arg(list, result |> Map.put(k, v))

  def check_server_address(arg) do
    case arg.server |> String.to_charlist() |> :inet.parse_address() do
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

  def check_edns(%{subnet: subnet} = arg) when is_binary(subnet),
    do: arg |> Map.put(:bufsize, DNS.edns_max_udpsize()) |> mk_edns_with_subnet

  def check_edns(arg) do
    arg
    |> Map.put(:bufsize, DNS.edns_max_udpsize())
    |> mk_edns
  end

  def mk_edns(arg) do
    arg
    |> Map.put(:edns, true)
    |> Map.put(:ex_rcode, 0)
    |> Map.put(:options, [])
  end

  def mk_edns_with_subnet(arg) do
    ecs_option = parse_subnet_option(arg.subnet)

    arg
    |> Map.put(:edns, true)
    |> Map.put(:ex_rcode, 0)
    |> Map.put(:options, [ecs_option])
  end

  @spec parse_subnet_option(String.t()) :: {atom(), map()}
  def parse_subnet_option(subnet) do
    case String.split(subnet, "/") do
      [addr_str, prefix_str] ->
        prefix = String.to_integer(prefix_str)

        case :inet.parse_address(String.to_charlist(addr_str)) do
          {:ok, {a, b, c, d}} ->
            # IPv4
            source_bits = min(prefix, 32)

            {:edns_client_subnet,
             %{
               family: 1,
               client_subnet: {a, b, c, d},
               source_prefix: source_bits,
               scope_prefix: 0
             }}

          {:ok, {a, b, c, d, e, f, g, h}} ->
            # IPv6
            source_bits = min(prefix, 128)

            {:edns_client_subnet,
             %{
               family: 2,
               client_subnet: {a, b, c, d, e, f, g, h},
               source_prefix: source_bits,
               scope_prefix: 0
             }}

          _ ->
            IO.puts(:stderr, "Invalid subnet address: #{addr_str}")
            System.halt(1)
        end

      _ ->
        IO.puts(:stderr, "Invalid subnet format. Use: address/prefix (e.g., 192.0.2.1/24)")
        System.halt(1)
    end
  end

  def check_args(%{help: true}), do: %{help: true, exit_code: 0}
  def check_args(%{name: nil, read: nil, version: nil}), do: %{help: true, exit_code: 1}

  def check_args(%{ptr: true} = args) do
    args
    |> Map.put(
      :name,
      (args[:name] |> String.split(".") |> Enum.reverse() |> tl |> Enum.join(".")) <>
        ".in-addr.arpa."
    )
    |> Map.put(:type, :ptr)
  end

  def check_args(arg) do
    arg
  end

  def process(%{version: true}), do: IO.puts("tdig #{version()}")

  def process(%{help: true, exit_code: exit_code}) do
    IO.puts("""
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
       --subnet <addr/len>    send EDNS Client Subnet option
    -s --sort                 sort RRs
    -r --read <file>          read packet from file
    -f        <file>          same as -r
    -w --write <file>         write answer packet to file
       --write-request <file> write request packet to file
    -v --version              print version and exit
    -h --help                 print help and exit
    """)

    System.halt(exit_code)
  end

  def process(arg) do
    arg
    |> Tdig.resolve()
  end
end
