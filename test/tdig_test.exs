defmodule TdigTest do
  use ExUnit.Case
  doctest Tdig

  describe "CLI argument parsing" do
    test "parse_switches converts string types to atoms" do
      assert Tdig.CLI.parse_switches({[type: "a", class: "in", port: 53], [], []}) == {[type: :a, class: :in, port: 53], [], []}
    end

    test "parse_switches handles mixed case types" do
      assert Tdig.CLI.parse_switches({[type: "AAAA", class: "IN"], [], []}) == {[type: :aaaa, class: :in], [], []}
    end

    test "parse_argv with domain and type" do
      assert Tdig.CLI.parse_argv({[], ["example.com.", "MX"], []}) == {[], %{name: "example.com.", type: :mx, class: nil, server: nil}, []}
    end

    test "parse_argv with server specification" do
      assert Tdig.CLI.parse_argv({[], ["@8.8.8.8", "example.com", "A"], []}) == {[], %{name: "example.com.", type: :a, class: nil, server: "8.8.8.8"}, []}
    end

    test "parse_argv with domain only defaults to root" do
      assert Tdig.CLI.parse_argv({[], [], []}) == {[], %{name: ".", type: nil, class: nil, server: nil}, []}
    end

    test "merge_switches_and_argv prioritizes switches over argv" do
      assert Tdig.CLI.merge_switches_and_argv({[type: :a, port: 53], %{name: "example.com.", type: :mx, class: :in}, []}) == %{name: "example.com.", type: :a, class: :in, port: 53}
    end
  end

  describe "string conversion utilities" do
    test "a2s converts atoms to uppercase strings" do
      assert Tdig.a2s(:cname) == "CNAME"
      assert Tdig.a2s(:a) == "A"
      assert Tdig.a2s(:aaaa) == "AAAA"
      assert Tdig.a2s(:mx) == "MX"
    end

    test "str2atom converts strings to lowercase atoms" do
      assert Tdig.CLI.str2atom("A") == :a
      assert Tdig.CLI.str2atom("CNAME") == :cname
      assert Tdig.CLI.str2atom("mx") == :mx
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
      assert result.bufsize == DNS.edns_max_udpsize
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
      assert Tdig.rdata_to_string(rdata, :a) == "192.168.1.1"
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
      assert Tdig.rdata_to_string(rdata, :txt) == "v=spf1 include:_spf.google.com ~all"
    end

    test "rdata_to_string handles unknown types" do
      rdata = %{unknown: "data"}
      result = Tdig.rdata_to_string(rdata, :unknown)
      assert is_binary(result)
      assert String.contains?(result, "unknown")
    end
  end

  describe "complete address formatting" do
    test "complete_addr formats IPv4 with partial subnet" do
      opt = %{family: 1, source: 24, addr: <<192, 168, 1>>}
      result = Tdig.complete_addr(opt)
      assert result == "192.168.1.0"
    end

    test "complete_addr formats IPv6 with partial subnet" do
      opt = %{family: 2, source: 64, addr: <<0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x00>>}
      result = Tdig.complete_addr(opt)
      assert String.contains?(result, "2001:db8")
    end
  end
end
