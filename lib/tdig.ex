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

    start = System.monotonic_time(:millisecond)

    socket
    |> Socket.Datagram.send(packet, {server, arg.port})

    socket 
    |> Socket.Datagram.recv!
    |> disp_response(start, System.monotonic_time(:millisecond))
  end

  def select_protocol(_, true) do
    {:inet6, 6}
  end

  def select_protocol(_, _) do
    {:inet, 4}
  end

  def disp_response({response, {server, port}}, start, finish) do
    response
    |> DNSpacket.parse
    |> disp_header
    |> disp_question
    |> disp_answer(:answer)
    |> disp_answer(:authority)
    |> disp_answer(:additional)

    disp_tailer(server |> :inet.ntoa |> to_string, port, response |> byte_size, finish - start)
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
    a
    |> Atom.to_string
    |> String.upcase
  end

  def disp_question(p) do
    IO.puts ";; QUESTION SECTION:"
    p.question
    |> Enum.map(fn n -> n |> question_item_to_string end)
    |> Enum.each(fn n -> n |> IO.puts end)
    IO.puts ""
    p
  end

  def question_item_to_string(q) do
    ";#{q.qname}			#{a2s(q.qclass)}	#{a2s(q.qtype)}"
  end
  
  def disp_answer(p, part) do
    IO.puts ";; #{a2s(part)} SECTION:"
    p[part]
    |> Enum.map(fn n-> n |> answer_item_to_string end)
    |> Enum.each(fn n -> n |> IO.puts end)
    IO.puts ""
    p
  end

  def answer_item_to_string(a) do
    """
#{a.name}		#{a.ttl}	#{a2s(a.class)}	#{a2s(a.type)}	#{a.rdata |> rdata_to_string(a.type)}
"""
  end

  def rdata_to_string(rdata, :a) do
    <<a1::8,a2::8,a3::8,a4::8>> = <<rdata.addr::32>>
    :inet.ntoa({a1,a2,a3,a4})
  end

  def rdata_to_string(rdata, :ns) do
    rdata.name
  end

  def rdata_to_string(rdata, :cname) do
    rdata.name
  end

  def rdata_to_string(rdata, :soa) do
    "#{rdata.mname} #{rdata.rname} #{rdata.serial} #{rdata.refresh} #{rdata.retry} #{rdata.expire} #{rdata.minimum}"
  end

  def rdata_to_string(rdata, :mx) do
    "#{rdata.preference} #{rdata.name}"
  end

  def rdata_to_string(rdata, :txt) do
    rdata.txt
  end

  def rdata_to_string(rdata, :aaaa) do
    <<a1::16,a2::16,a3::16,a4::16,a5::16,a6::16,a7::16,a8::16>> = <<rdata.addr::128>>
    :inet.ntoa({a1,a2,a3,a4,a5,a6,a7,a8})
  end

  def rdata_to_string(rdata, :caa) do
    "#{rdata.flag} #{rdata.tag} #{rdata.value}"
  end

  def rdata_to_string(rdata, _type) do
    "#{inspect(rdata)}"
  end

  def disp_tailer(server, port, size, time) do
    IO.puts """
;; Query time: #{time} ms
;; SERVER: #{server}##{port}(#{server})
;; WHEN: #{DateTime.now!("Asia/Tokyo") |> DateTime.to_string}
;; MSG SIZE rcvd: #{size}
"""
  end
end
