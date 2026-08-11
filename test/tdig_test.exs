defmodule TdigTest do
  use ExUnit.Case

  describe "CLI argument parsing" do
    test "parse_switches converts string types to atoms" do
      assert Tdig.CLI.parse_switches({[type: "a", class: "in", port: 53], [], []}) ==
               {[type: :a, class: :in, port: 53], [], []}
    end

    test "parse_switches handles mixed case types" do
      assert Tdig.CLI.parse_switches({[type: "AAAA", class: "IN"], [], []}) ==
               {[type: :aaaa, class: :in], [], []}
    end

    test "parse_argv with domain and type" do
      assert Tdig.CLI.parse_argv({[], ["example.com.", "MX"], []}) ==
               {[], %{name: "example.com.", type: :mx, class: nil, server: nil}, []}
    end

    test "parse_argv with server specification" do
      assert Tdig.CLI.parse_argv({[], ["@8.8.8.8", "example.com", "A"], []}) ==
               {[], %{name: "example.com.", type: :a, class: nil, server: "8.8.8.8"}, []}
    end

    test "parse_argv with domain only defaults to root" do
      assert Tdig.CLI.parse_argv({[], [], []}) ==
               {[], %{name: ".", type: nil, class: nil, server: nil}, []}
    end

    test "merge_switches_and_argv prioritizes switches over argv" do
      assert Tdig.CLI.merge_switches_and_argv(
               {[type: :a, port: 53], %{name: "example.com.", type: :mx, class: :in}, []}
             ) == %{name: "example.com.", type: :a, class: :in, port: 53}
    end
  end

  describe "string conversion utilities" do
    test "a2s converts atoms to uppercase strings" do
      assert Tdig.a2s(:cname) == "CNAME"
      assert Tdig.a2s(:a) == "A"
      assert Tdig.a2s(:aaaa) == "AAAA"
      assert Tdig.a2s(:mx) == "MX"
    end

    test "parse_type converts known type names to lowercase atoms" do
      assert Tdig.CLI.parse_type("A") == :a
      assert Tdig.CLI.parse_type("CNAME") == :cname
      assert Tdig.CLI.parse_type("mx") == :mx
    end

    test "parse_type returns nil for unknown type names" do
      assert Tdig.CLI.parse_type("foo") == nil
      assert Tdig.CLI.parse_type("sony.com") == nil
      # a known atom that is not an RR type must not be accepted
      assert Tdig.CLI.parse_type("help") == nil
    end

    test "parse_class converts known class names to lowercase atoms" do
      assert Tdig.CLI.parse_class("IN") == :in
      assert Tdig.CLI.parse_class("ch") == :ch
    end

    test "parse_class returns nil for unknown class names" do
      assert Tdig.CLI.parse_class("foo") == nil
      # RR type names are not classes
      assert Tdig.CLI.parse_class("txt") == nil
    end
  end

  describe "dig-compatible argument order (Issue #77)" do
    test "parse_argv accepts type before name" do
      assert Tdig.CLI.parse_argv({[], ["txt", "sony.com"], []}) ==
               {[], %{name: "sony.com.", type: :txt, class: nil, server: nil}, []}
    end

    test "parse_argv accepts uppercase type before name" do
      assert Tdig.CLI.parse_argv({[], ["TXT", "sony.com"], []}) ==
               {[], %{name: "sony.com.", type: :txt, class: nil, server: nil}, []}
    end

    test "parse_argv accepts class and type in any position" do
      assert Tdig.CLI.parse_argv({[], ["ch", "txt", "version.bind"], []}) ==
               {[], %{name: "version.bind.", type: :txt, class: :ch, server: nil}, []}
    end

    test "parse_argv resolves any as type, not class" do
      assert Tdig.CLI.parse_argv({[], ["any", "example.com"], []}) ==
               {[], %{name: "example.com.", type: :any, class: nil, server: nil}, []}
    end

    test "parse_argv keeps name-first order working" do
      assert Tdig.CLI.parse_argv({[], ["sony.com", "txt"], []}) ==
               {[], %{name: "sony.com.", type: :txt, class: nil, server: nil}, []}
    end

    test "parse_argv with server, type and name in dig order" do
      assert Tdig.CLI.parse_argv({[], ["@8.8.8.8", "txt", "sony.com"], []}) ==
               {[], %{name: "sony.com.", type: :txt, class: nil, server: "8.8.8.8"}, []}
    end

    test "trailing dot forces a type-like token to be a name" do
      # querying a host literally named "txt" is still possible, as in dig
      assert Tdig.CLI.parse_argv({[], ["txt."], []}) ==
               {[], %{name: "txt.", type: nil, class: nil, server: nil}, []}
    end

    test "unknown token becomes the name instead of an invalid type" do
      # previously this token was force-converted to a type atom and
      # crashed packet creation with ArgumentError (Issue #77)
      assert Tdig.CLI.parse_argv({[], ["not-a-type"], []}) ==
               {[], %{name: "not-a-type.", type: nil, class: nil, server: nil}, []}
    end
  end

  describe "domain name handling" do
    test "add_tail_dot preserves existing dot" do
      assert Tdig.CLI.add_tail_dot("example.com.") == "example.com."
    end

    test "add_tail_dot adds missing dot" do
      assert Tdig.CLI.add_tail_dot("example.com") == "example.com."
    end

    test "add_tail_dot handles root domain" do
      assert Tdig.CLI.add_tail_dot(".") == "."
    end

    test "add_tail_dot handles empty string" do
      assert Tdig.CLI.add_tail_dot("") == "."
    end
  end

  describe "server address parsing" do
    test "check_server_address detects IPv4" do
      arg = %{server: "192.168.1.1"}
      result = Tdig.CLI.check_server_address(arg)
      assert result.v4 == true
      assert result.v6 == false
    end

    test "check_server_address detects IPv6" do
      arg = %{server: "2001:db8::1"}
      result = Tdig.CLI.check_server_address(arg)
      assert result.v4 == false
      assert result.v6 == true
    end

    test "check_server_address handles hostname" do
      arg = %{server: "dns.google.com", v4: true, v6: false}
      result = Tdig.CLI.check_server_address(arg)
      assert result.v4 == true
      assert result.v6 == false
    end
  end

  describe "EDNS handling" do
    test "check_edns enables EDNS when bufsize is specified" do
      arg = %{bufsize: 4096}
      result = Tdig.CLI.check_edns(arg)
      assert result.edns == true
      assert result.bufsize == 4096
      assert result.ex_rcode == 0
      assert result.options == []
    end

    test "check_edns skips when edns is false" do
      arg = %{edns: false}
      result = Tdig.CLI.check_edns(arg)
      assert result.edns == false
    end

    test "check_edns sets default bufsize" do
      arg = %{}
      result = Tdig.CLI.check_edns(arg)
      assert result.edns == true
      assert result.bufsize == DNS.edns_max_udpsize()
    end
  end

  describe "PTR record handling" do
    test "check_args converts IPv4 for PTR lookup" do
      arg = %{ptr: true, name: "192.168.1.1."}
      result = Tdig.CLI.check_args(arg)
      assert result.name == "1.1.168.192.in-addr.arpa."
      assert result.type == :ptr
    end
  end

  describe "protocol selection" do
    test "select_protocol chooses IPv6 when v6 is true" do
      assert Tdig.select_protocol(true, true) == {:inet6, 6}
    end

    test "select_protocol chooses IPv4 by default" do
      assert Tdig.select_protocol(true, false) == {:inet, 4}
      assert Tdig.select_protocol(false, false) == {:inet, 4}
    end
  end

  describe "answer formatting" do
    test "sort_answer sorts by type when enabled" do
      answers = [
        %{type: :mx, name: "example.com"},
        %{type: :a, name: "example.com"},
        %{type: :cname, name: "example.com"}
      ]

      result = Tdig.sort_answer(answers, true)
      assert Enum.at(result, 0).type == :a
      assert Enum.at(result, 1).type == :cname
      assert Enum.at(result, 2).type == :mx
    end

    test "sort_answer preserves order when disabled" do
      answers = [
        %{type: :mx, name: "example.com"},
        %{type: :a, name: "example.com"}
      ]

      result = Tdig.sort_answer(answers, false)
      assert Enum.at(result, 0).type == :mx
      assert Enum.at(result, 1).type == :a
    end
  end

  describe "rdata formatting" do
    test "rdata_to_string formats A records" do
      rdata = %{addr: {192, 168, 1, 1}}
      assert Tdig.rdata_to_string(rdata, :a) == ~c"192.168.1.1"
    end

    test "rdata_to_string formats MX records" do
      rdata = %{preference: 10, name: "mail.example.com"}
      assert Tdig.rdata_to_string(rdata, :mx) == "10 mail.example.com"
    end

    test "rdata_to_string formats CNAME records" do
      rdata = %{name: "alias.example.com"}
      assert Tdig.rdata_to_string(rdata, :cname) == "alias.example.com"
    end

    test "rdata_to_string formats NS records" do
      rdata = %{name: "ns1.example.com"}
      assert Tdig.rdata_to_string(rdata, :ns) == "ns1.example.com"
    end

    test "rdata_to_string formats TXT records" do
      rdata = %{txt: "v=spf1 include:_spf.google.com ~all"}
      assert Tdig.rdata_to_string(rdata, :txt) == ~s("v=spf1 include:_spf.google.com ~all")
    end

    test "rdata_to_string escapes double quotes inside TXT records" do
      rdata = %{txt: ~s(a"b)}
      assert Tdig.rdata_to_string(rdata, :txt) == ~S("a\"b")
    end

    test "rdata_to_string escapes backslashes inside TXT records" do
      rdata = %{txt: ~S(a\b)}
      assert Tdig.rdata_to_string(rdata, :txt) == ~S("a\\b")
    end

    test "rdata_to_string escapes non-printable bytes inside TXT records" do
      # Terminal escape sequences must not survive into the output; dig renders
      # non-printable octets as three-digit decimal escapes.
      rdata = %{txt: <<0x1B, "[31m">>}
      assert Tdig.rdata_to_string(rdata, :txt) == ~S("\027[31m")
    end

    test "rdata_to_string renders an empty TXT record as empty quotes" do
      rdata = %{txt: ""}
      assert Tdig.rdata_to_string(rdata, :txt) == ~s("")
    end

    test "rdata_to_string leaves domain names unquoted" do
      # dig quotes TXT character-strings but not domain names; the TXT-specific
      # quoting must not leak into the shared escape/1 path.
      assert Tdig.rdata_to_string(%{name: "ns1.example.com"}, :ns) == "ns1.example.com"
      assert Tdig.rdata_to_string(%{name: "alias.example.com"}, :cname) == "alias.example.com"

      assert Tdig.rdata_to_string(%{preference: 10, name: "mail.example.com"}, :mx) ==
               "10 mail.example.com"
    end

    test "rdata_to_string handles unknown types" do
      rdata = %{unknown: "data"}
      result = Tdig.rdata_to_string(rdata, :unknown)
      assert is_binary(result)
      assert String.contains?(result, "unknown")
    end
  end

  describe "subnet functionality" do
    test "parse_subnet_option handles IPv4 subnet" do
      result = Tdig.CLI.parse_subnet_option("192.0.2.1/24")
      assert elem(result, 0) == :edns_client_subnet
      ecs_data = elem(result, 1)
      assert ecs_data.family == 1
      assert ecs_data.source_prefix == 24
      assert ecs_data.scope_prefix == 0
      assert ecs_data.client_subnet == {192, 0, 2, 1}
    end

    test "parse_subnet_option handles IPv4 subnet with /32" do
      result = Tdig.CLI.parse_subnet_option("10.0.0.1/32")
      assert elem(result, 0) == :edns_client_subnet
      ecs_data = elem(result, 1)
      assert ecs_data.family == 1
      assert ecs_data.source_prefix == 32
      assert ecs_data.scope_prefix == 0
      assert ecs_data.client_subnet == {10, 0, 0, 1}
    end

    test "parse_subnet_option handles IPv6 subnet" do
      result = Tdig.CLI.parse_subnet_option("2001:db8::1/64")
      assert elem(result, 0) == :edns_client_subnet
      ecs_data = elem(result, 1)
      assert ecs_data.family == 2
      assert ecs_data.source_prefix == 64
      assert ecs_data.scope_prefix == 0
      assert ecs_data.client_subnet == {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}
    end

    test "check_edns enables EDNS with subnet option" do
      arg = %{subnet: "192.0.2.1/24"}
      result = Tdig.CLI.check_edns(arg)
      assert result.edns == true
      assert result.bufsize == DNS.edns_max_udpsize()
      assert length(result.options) == 1

      ecs_option = List.first(result.options)
      assert elem(ecs_option, 0) == :edns_client_subnet
      ecs_data = elem(ecs_option, 1)
      assert ecs_data.family == 1
      assert ecs_data.source_prefix == 24
    end
  end

  describe "subnet prefix length validation (Issue #86)" do
    # dig parses the prefix as an unsigned number and refuses anything else
    # ("invalid prefix length in '...': not a valid number"), so a negative or
    # non-numeric value is an error rather than something to coerce.
    test "parse_prefix_length/1 accepts a bare non-negative number" do
      assert Tdig.CLI.parse_prefix_length("24") == {:ok, 24}
      assert Tdig.CLI.parse_prefix_length("0") == {:ok, 0}
      # dig accepts leading zeros: 192.0.2.1/024 => CLIENT-SUBNET: 192.0.2.0/24/0
      assert Tdig.CLI.parse_prefix_length("024") == {:ok, 24}
    end

    test "parse_prefix_length/1 rejects a negative number" do
      assert Tdig.CLI.parse_prefix_length("-5") == :error
      assert Tdig.CLI.parse_prefix_length("-1") == :error
    end

    test "parse_prefix_length/1 rejects anything that is not a bare number" do
      for input <- ["abc", "", " 24", "24x", "2.4", "+24"] do
        assert Tdig.CLI.parse_prefix_length(input) == :error,
               "expected #{inspect(input)} to be rejected"
      end
    end

    # An over-range prefix is NOT an error in dig: it is capped at the address
    # family's width. Measured with dig 9.20.26 via +qr:
    #   192.0.2.1/999   => CLIENT-SUBNET: 192.0.2.1/32/0
    #   2001:db8::1/200 => CLIENT-SUBNET: 2001:db8::1/128/0
    test "an over-range IPv4 prefix is clamped to 32 rather than rejected" do
      {:edns_client_subnet, ecs} = Tdig.CLI.parse_subnet_option("192.0.2.1/999")
      assert ecs.source_prefix == 32

      {:edns_client_subnet, ecs} = Tdig.CLI.parse_subnet_option("192.0.2.1/33")
      assert ecs.source_prefix == 32
    end

    test "an over-range IPv6 prefix is clamped to 128 rather than rejected" do
      {:edns_client_subnet, ecs} = Tdig.CLI.parse_subnet_option("2001:db8::1/200")
      assert ecs.source_prefix == 128
    end

    test "an extra slash is a format error, not a prefix error" do
      # split_subnet/1 is where parse_subnet_option/1 decides between its two
      # error messages. Asserting it directly, rather than the halting call,
      # keeps the distinction testable: :error here means the input never
      # reaches parse_prefix_length/1 and gets the format message instead.
      assert Tdig.CLI.split_subnet("192.0.2.1/24/8") == :error
      assert Tdig.CLI.split_subnet("192.0.2.1//24") == :error
      assert Tdig.CLI.split_subnet("192.0.2.1") == :error

      assert Tdig.CLI.split_subnet("192.0.2.1/24") == {:ok, "192.0.2.1", "24"}
      # an empty prefix is a well-formed split, so it is a prefix error
      assert Tdig.CLI.split_subnet("2001:db8::1/") == {:ok, "2001:db8::1", ""}
      assert Tdig.CLI.parse_prefix_length("") == :error
    end

    test "a prefix far above the family width is still clamped" do
      # dig stops at a 32-bit unsigned and reports "out of range" beyond it
      # (4294967295 clamps to 32, 4294967296 errors), which is an artefact of
      # its C parsing rather than a protocol limit. tdig has no such ceiling;
      # every value at or above the family width produces the same option, so
      # the emitted query matches dig for everything dig accepts.
      {:edns_client_subnet, ecs} = Tdig.CLI.parse_subnet_option("192.0.2.1/4294967295")
      assert ecs.source_prefix == 32

      {:edns_client_subnet, ecs} = Tdig.CLI.parse_subnet_option("192.0.2.1/99999999999999999999")
      assert ecs.source_prefix == 32
    end
  end

  describe "subnet option reaches the query (Issue #86)" do
    # parse_args/1 sets :edns via Map.put_new, so the key is always present.
    # These go through parse_args rather than calling check_edns/1 with a
    # hand-built map, because the shadowing bug was invisible to a map that
    # omitted :edns.
    defp ecs_options(argv), do: Tdig.CLI.parse_args(argv)[:options]

    test "--subnet alone carries the ECS option" do
      assert [{:edns_client_subnet, ecs}] =
               ecs_options(["example.com", "--subnet", "192.0.2.1/24"])

      assert ecs.family == 1
      assert ecs.source_prefix == 24
    end

    test "--subnet combined with --bufsize carries the ECS option" do
      argv = ["example.com", "--bufsize", "1232", "--subnet", "192.0.2.1/24"]
      assert [{:edns_client_subnet, ecs}] = ecs_options(argv)
      assert ecs.source_prefix == 24
    end

    test "--subnet keeps an explicitly requested bufsize" do
      argv = ["example.com", "--bufsize", "1232", "--subnet", "192.0.2.1/24"]
      assert Tdig.CLI.parse_args(argv)[:bufsize] == 1232
    end

    test "--subnet with --bufsize reaches the OPT record that gets sent" do
      # parse_args/1 alone does not prove the value is emitted: the OPT
      # pseudo-record is built later, in Tdig.check_edns/1.
      argv = ["example.com", "--bufsize", "1232", "--subnet", "192.0.2.1/24"]
      assert [opt] = argv |> Tdig.CLI.parse_args() |> Tdig.check_edns()
      assert opt.type == :opt
      assert opt.payload_size == 1232
      assert [{:edns_client_subnet, ecs}] = opt.rdata
      assert ecs.source_prefix == 24
    end

    test "--subnet combined with --edns still carries the ECS option" do
      argv = ["example.com", "--edns", "--subnet", "192.0.2.1/24"]
      assert [{:edns_client_subnet, _}] = ecs_options(argv)
    end

    test "--subnet turns EDNS on, as dig's +subnet does" do
      assert Tdig.CLI.parse_args(["example.com", "--subnet", "192.0.2.1/24"])[:edns] == true
    end

    test "EDNS without a subnet carries no options" do
      assert ecs_options(["example.com", "--edns"]) == []
      assert ecs_options(["example.com", "--bufsize", "1232"]) == []
    end

    test "a plain query still has EDNS off" do
      args = Tdig.CLI.parse_args(["example.com"])
      assert args[:edns] == false
      assert args[:options] == nil
    end
  end

  describe "version reporting (Issue #49)" do
    test "version/0 returns the mix.exs project version" do
      # Guards against stale hardcoded version strings drifting from mix.exs.
      assert Tdig.CLI.version() == Mix.Project.config()[:version]
    end

    test "version/0 is a non-empty semver-shaped string" do
      version = Tdig.CLI.version()
      assert is_binary(version)

      assert String.match?(version, ~r/^\d+\.\d+\.\d+/),
             "expected semver, got #{inspect(version)}"
    end
  end

  describe "help functionality" do
    @tag :help
    test "parse_args identifies help option with -h" do
      result = Tdig.CLI.parse_args(["-h"])
      assert result.help == true
      assert result.exit_code == 0
    end

    @tag :help
    test "parse_args identifies help option with --help" do
      result = Tdig.CLI.parse_args(["--help"])
      assert result.help == true
      assert result.exit_code == 0
    end

    @tag :help
    test "parse_args defaults to help when no name provided" do
      result = Tdig.CLI.parse_args([])

      # 引数なしの場合、nameは"."にデフォルト設定されるため、helpフラグは設定されない
      assert result.name == "."
      assert Map.get(result, :help) == nil
    end
  end

  describe "terminal output escaping (G)" do
    test "escape/1 passes printable ASCII through unchanged" do
      assert Tdig.escape("example.com.") == "example.com."
      assert Tdig.escape("a-b_c 123!") == "a-b_c 123!"
    end

    test "escape/1 renders control and non-printable bytes as \\DDD" do
      # ESC (0x1B) — the byte that starts ANSI/OSC sequences — must not pass through.
      assert Tdig.escape(<<0x1B, "[31mX">>) == "\\027[31mX"
      assert Tdig.escape(<<0, 9, 10, 13>>) == "\\000\\009\\010\\013"
      assert Tdig.escape(<<0x7F>>) == "\\127"
      # high byte
      assert Tdig.escape(<<0xFF>>) == "\\255"
    end

    test "escape/1 escapes backslash so the encoding is unambiguous" do
      assert Tdig.escape("a\\b") == "a\\\\b"
    end

    test "rdata_to_string escapes untrusted TXT and name bytes" do
      # TXT is additionally wrapped in quotes to match dig; the escaping of the
      # ESC byte is what matters here.
      assert Tdig.rdata_to_string(%{txt: <<"hi", 0x1B, "!">>}, :txt) == ~S("hi\027!")

      assert Tdig.rdata_to_string(%{name: <<"ns", 0x1B, ".example.">>}, :cname) ==
               "ns\\027.example."

      assert Tdig.rdata_to_string(%{flag: 0, tag: "issue", value: <<0x1B, "ca">>}, :caa) ==
               "0 issue \\027ca"
    end

    test "answer_item_to_string escapes the owner name" do
      line =
        Tdig.answer_item_to_string(%{
          name: <<"host", 0x1B, ".example.">>,
          ttl: 60,
          class: :in,
          type: :a,
          rdata: %{addr: {192, 0, 2, 1}}
        })

      refute line =~ <<0x1B>>
      assert line =~ "host\\027.example."
    end

    test "question_item_to_string escapes the qname" do
      line = Tdig.question_item_to_string(%{qname: <<"q", 0x1B, ".">>, qclass: :in, qtype: :a})
      refute line =~ <<0x1B>>
      assert line =~ "q\\027."
    end
  end
end
