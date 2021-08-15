defmodule Tdig do
  @moduledoc """
  Documentation for `Tdig`.
  """

  def resolve(arg) do
    {family, version} = select_protocol(arg.v4, arg.v6)
    socket = Socket.UDP.open!([version: version])

    {:ok, server} = arg.server
    |> String.to_charlist
    |> :inet.getaddr(family)

    packet = %{
      id: :rand.uniform(0xffff),
      flags: 0x0100,
      question: [
        %{
          qname: arg.name,
          qtype: arg.type,
          qclass: arg.class,
        }
      ],
      answer: [],
      authority: [],
      additional: [],
    }
    |> DNSpacket.create

    socket
    |> Socket.Datagram.send(packet, {server, arg.port})

    socket 
    |> Socket.Datagram.recv!
    |> disp_response
  end

  def select_protocol(_, true) do
    {:inet6, 6}
  end

  def select_protocol(_, _) do
    {:inet, 4}
  end

  def disp_response({answer, _}) do
    answer
    |> DNSpacket.parse
    |> disp_header
    |> disp_question
    |> disp_answer(:answer)
    |> disp_answer(:authority)
    |> disp_answer(:additional)
  end

  defp qr(0) do
    " q"
  end

  defp qr(1) do
    " r"
  end

  defp opcode(0) do
    "QUERY"
  end

  defp opcode(1) do
    "IQUERY"
  end

  defp opcode(2) do
    "STATUS"
  end

  defp opcode(op) do
    "reserved(#{op})"
  end

  defp aa(0) do
    ""
  end

  defp aa(1) do
    " aa"
  end

  defp tc(0) do
    ""
  end

  defp tc(1) do
    " tc"
  end

  defp rd(0) do
    ""
  end

  defp rd(1) do
    " rd"
  end

  defp ra(0) do
    ""
  end

  defp ra(1) do
    " ra"
  end

  defp z(0) do
    ""
  end

  defp z(1) do
    " z"
  end

  defp rcode(0) do
    "No error condition"
  end

  defp rcode(1) do
    "Format error"
  end

  defp rcode(2) do
    "Server failure"
  end

  defp rcode(3) do
    "Name Error"
  end

  defp rcode(4) do
    "Not Implemented"
  end

  defp rcode(5) do
    "Refused"
  end

  defp rcode(rc) do
    "reserved(#{rc})"
  end

  def disp_header(p) do
    IO.puts """
;; ->>HEADER<<- opcode: #{opcode(p.opcode)}, status: #{rcode(p.rcode)}, id: #{p.id}
;; flags:#{qr(p.qr)}#{aa(p.aa)}#{tc(p.tc)}#{rd(p.rd)}#{ra(p.rd)}#{z(p.z)}; QUERY: #{length(p.question)}, ANSWER #{length(p.answer)}, AUTHORITY: #{length(p.authority)}, ADDITIONAL: #{length(p.additional)}
"""
    p
  end

  def a2s(a) do
    String.upcase(Atom.to_string(a))
  end

  def disp_question(p) do
    IO.puts ";; QUESTION SECTION:"
    disp_question_item(p.question)
    IO.puts ""
    p
  end

  def disp_question_item([]) do
  end

  def disp_question_item(([q|tail])) do
    IO.puts ";#{q.qname}			#{a2s(q.qclass)}	#{a2s(q.qtype)}"
    disp_question_item(tail)
  end

  def disp_answer(p, part) do
    IO.puts ";; #{a2s(part)} SECTION:"
    disp_answer_item(p[part])
    IO.puts ""
    p
  end

  def disp_answer_item([]) do
  end

  def disp_answer_item([a|tail]) do
    IO.write "#{a.name}		#{a.ttl}	#{a2s(a.class)}	#{a2s(a.type)}	"
    disp_rdata(a.type, a.rdata)
    disp_answer_item(tail)
  end

  def disp_rdata(:a, rdata) do
    <<a1::8,a2::8,a3::8,a4::8>> = <<rdata.addr::32>>
    IO.puts :inet.ntoa({a1,a2,a3,a4})
  end

  def disp_rdata(:ns, rdata) do
    IO.puts rdata.name
  end

  def disp_rdata(:cname, rdata) do
    IO.puts rdata.name
  end

  def disp_rdata(:soa, rdata) do
    IO.puts "#{rdata.mname} #{rdata.rname} #{rdata.serial} #{rdata.refresh} #{rdata.retry} #{rdata.expire} #{rdata.minimum}"
  end

  def disp_rdata(:mx, rdata) do
    IO.puts "#{rdata.preference} #{rdata.name}"
  end

  def disp_rdata(:txt, rdata) do
    IO.puts rdata.txt
  end

  def disp_rdata(:aaaa, rdata) do
    <<a1::16,a2::16,a3::16,a4::16,a5::16,a6::16,a7::16,a8::16>> = <<rdata.addr::128>>
    IO.puts :inet.ntoa({a1,a2,a3,a4,a5,a6,a7,a8})
  end

  def disp_rdata(:caa, rdata) do
    IO.puts "#{rdata.flag} #{rdata.tag} #{rdata.value}"
  end

  def disp_rdata(_type, rdata) do
    IO.puts "#{inspect(rdata)}"
  end
end
