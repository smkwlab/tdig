defmodule TdigTest do
  use ExUnit.Case
  doctest Tdig

  test "parse_switches" do
    assert Tdig.CLI.parse_switches({[type: "a", class: "in", port: 53], [], []}) == {[type: :a, class: :in, port: 53], [], []}
  end

  test "parse_argv" do
    assert Tdig.CLI.parse_argv({[], ["example.com.", "MX"], []}) == {[], %{name: "example.com.", type: :mx, class: nil, server: nil}, []}
  end

  test "merge_switches_and_argv" do
    assert Tdig.CLI.merge_switches_and_argv({[type: :a, port: 53], %{name: "example.com.", type: :mx, class: :in}, []}) == %{name: "example.com.", type: :a, class: :in, port: 53}
  end

  test "add_default" do
    arg = %{server: "dns.google.", port: 53}
    assert Tdig.CLI.add_default(arg, :type, :a) == %{server: "dns.google.", port: 53, type: :a}
    assert Tdig.CLI.add_default(arg, :port, 55) == %{server: "dns.google.", port: 53}
  end

  test "a2p" do
    assert Tdig.a2s(:cname) == "CNAME"
  end
  
  test "add_tail_dot" do
    assert Tdig.CLI.add_tail_dot("example.com.") == "example.com."
    assert Tdig.CLI.add_tail_dot("example.com") == "example.com."
  end
end
