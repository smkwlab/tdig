defmodule Tdig do
  @moduledoc """
  Documentation for `Tdig`.
  """

  def resolve(arg) do
    start = System.monotonic_time(:millisecond)
    
    arg
    |> get_response
    |> write_file(arg.write)
    |> disp_response(start, System.monotonic_time(:millisecond))
  end

  def get_response(%{read: nil} = arg) do
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
    |> write_file(arg.write_request)

    {family, version} = select_protocol(arg.v4, arg.v6)
    socket = Socket.UDP.open!([version: version])

    {:ok, server} = arg.server
    |> String.to_charlist
    |> :inet.getaddr(family)

    
    Socket.Datagram.send(socket, packet, {server, arg.port})
    Socket.Datagram.recv!(socket)
  end

  def get_response(arg) do
    {File.read!(arg.read), {{0,0,0,0}, "  '#{arg.read}'  "}}
  end

  def write_file(packet, nil) do
    packet
  end
      
  def write_file({packet, _} = result, file) do
    :ok = File.write(file, packet)
    result
  end

  def write_file(packet, file) do
    :ok = File.write(file, packet)
    packet
  end

  def select_protocol(_, true), do: {:inet6, 6}
  def select_protocol(_, _),    do: {:inet, 4}

  def disp_response({response, {server, port}}, start, finish) do
    response
    |> DNSpacket.parse
    |> disp_header
    |> disp_edns_pseudo
    |> disp_question
    |> disp_answer(:answer)
    |> disp_answer(:authority)
    |> disp_answer(:additional)

    disp_tailer(server |> :inet.ntoa |> to_string, port, byte_size(response), finish - start)
  end

  defp qr(0), do: " q"
  defp qr(1), do: " r"

  defp opcode(0), do: "QUERY"
  defp opcode(1), do: "IQUERY"
  defp opcode(2), do: "STATUS"
  defp opcode(op), do: "reserved(#{op})"

  defp aa(0), do: ""
  defp aa(1), do: " aa"

  defp tc(0), do: ""
  defp tc(1), do: " tc"

  defp rd(0), do: ""
  defp rd(1), do: " rd"

  defp ra(0), do: ""
  defp ra(1), do: " ra"

  defp z(0), do: ""
  defp z(1), do: " z"

  def disp_header(p) do
    IO.puts """
;; ->>HEADER<<- opcode: #{opcode(p.opcode)}, status: #{DNS.rcode_text[DNS.rcode[p.rcode]]}, id: #{p.id}
;; flags:#{qr(p.qr)}#{aa(p.aa)}#{tc(p.tc)}#{rd(p.rd)}#{ra(p.rd)}#{z(p.z)}; QUERY: #{length(p.question)}, ANSWER #{length(p.answer)}, AUTHORITY: #{length(p.authority)}, ADDITIONAL: #{length(p.additional)}
"""
    p
  end

  def a2s(a) do
    a
    |> Atom.to_string
    |> String.upcase
  end

  def disp_edns_pseudo(p) do
    p.additional
    |> Enum.filter(fn n -> n.type == :opt end)
    |> disp_edns_pseudo_item
    p
  end
  
  def disp_edns_pseudo_item([]), do: nil

  def disp_edns_pseudo_item([%{type: :opt} = p]) do
    IO.puts ";; OPT PSEUDOSECTION:"
    IO.puts "; EDNS: version: #{p.version}, flags:; udp: #{p.payload_size}"
  end

  def disp_question(p) do
    IO.puts ";; QUESTION SECTION:"
    p.question
    |> Enum.map(fn n -> question_item_to_string(n) end)
    |> Enum.each(fn n -> IO.puts(n) end)
    IO.puts ""
    p
  end

  def question_item_to_string(q) do
    ";#{q.qname}			#{q.qclass |> a2s}	#{q.qtype |> a2s}"
  end
  
  def disp_answer(p, part) do
    IO.puts ";; #{a2s(part)} SECTION:"
    p[part]
    |> Enum.map(fn n-> answer_item_to_string(n) end)
    |> Enum.each(fn n -> IO.write(n) end)
    IO.puts ""
    p
  end

  # Do not display OPT item in answer
  def answer_item_to_string(%{type: :opt}), do: ""

  def answer_item_to_string(a) do """
    #{a.name}		#{a.ttl}	#{a.class|>a2s}	#{a.type|>a2s}	#{a.rdata|>rdata_to_string(a.type)}
    """
  end

  def rdata_to_string(rdata, :a), do: :inet.ntoa(rdata.addr)
  def rdata_to_string(rdata, :aaaa), do: :inet.ntoa(rdata.addr)
  def rdata_to_string(rdata, :ns), do: rdata.name
  def rdata_to_string(rdata, :cname), do: rdata.name
  def rdata_to_string(rdata, :txt), do: rdata.txt
  def rdata_to_string(rdata, :mx), do: "#{rdata.preference} #{rdata.name}"
  def rdata_to_string(rdata, :caa), do: "#{rdata.flag} #{rdata.tag} #{rdata.value}"

  def rdata_to_string(rdata, :soa),
    do: "#{rdata.mname} #{rdata.rname} #{rdata.serial} #{rdata.refresh} #{rdata.retry} #{rdata.expire} #{rdata.minimum}"

  def rdata_to_string(rdata, _), do: inspect(rdata)

  def disp_tailer(server, port, size, time) do
    IO.puts """
    ;; Query time: #{time} ms
    ;; SERVER: #{server}##{port}(#{server})
    ;; WHEN: #{"Asia/Tokyo" |> DateTime.now! |> DateTime.to_string}
    ;; MSG SIZE rcvd: #{size}
    """
  end
end
