defmodule Tdig do
  @moduledoc """
  Documentation for `Tdig`.
  """

  def resolve(arg) do
    start = System.monotonic_time(:millisecond)
    
    arg
    |> get_response
    |> write_file(arg.write)
    |> disp_response(arg, System.monotonic_time(:millisecond) - start)
  end

  def get_response(%{read: file}) when is_binary(file),
    do: {File.read!(file), {{0,0,0,0}, "  '#{file}'  "}}

  def get_response(arg) do
    %{
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
      additional: check_edns(arg),
    }
    |> DNSpacket.create
    |> write_file(arg.write_request)
    |> send_server(arg)
  end

  def check_edns(%{edns: false}), do: []

  # FIXME
  def check_edns(arg) do
    [
      %{
        type: :opt,
        bufsize: arg.bufsize,
        ex_rcode: arg.ex_rcode,
        version: 0,
        dnssec: 0,
        z: 0,
        options: arg.options,
      }
    ]
  end

  def send_server(packet, %{tcp: true} = arg) do
    {family, version} = select_protocol(arg.v4, arg.v6)
    {:ok, socket} = Socket.TCP.connect(arg.server, arg.port, [version: version])

    :ok = Socket.Stream.send(socket, <<byte_size(packet)::16>> <> packet)
    {:ok, <<length::16>>} = Socket.Stream.recv(socket, 2)
    {:ok, <<response::binary-size(length)>>} = Socket.Stream.recv(socket, length)
    Socket.close(socket)

    {:ok, server} =
      arg.server
      |> String.to_charlist
      |> :inet.getaddr(family)

    {response, {server, arg.port}}
  end

  def send_server(packet, arg) do
    {_, version} = select_protocol(arg.v4, arg.v6)
    socket = Socket.UDP.open!([version: version])

    :ok = Socket.Datagram.send(socket, packet, {arg.server, arg.port})
    Socket.Datagram.recv!(socket)
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

  def disp_response({response, {server, port}}, arg, period) do
    response
    |> DNSpacket.parse
    |> check_tc_flag(arg)
    |> disp_header
    |> disp_edns_pseudo_header
    |> disp_question
    |> disp_answer(:answer, arg[:sort])
    |> disp_answer(:authority, arg[:sort])
    |> disp_answer(:additional, arg[:sort])

    disp_tailer(server |> :inet.ntoa |> to_string, port, byte_size(response), period)
  end

  def check_tc_flag(%{tc: 1}, %{ignore: false} = arg) do
    IO.puts """
    ;; Truncated, retrying in TCP mode.
    """
    
    resolve(Map.put(arg, :tcp, true))
    System.halt(0)
  end

  def check_tc_flag(response, _) do
    response
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

  def disp_edns_pseudo_header(p) do
    p.additional
    |> Enum.filter(fn n -> n.type == :opt end)
    |> disp_edns_opt_record

    p
  end
  
  def disp_edns_opt_record([]), do: nil

  def disp_edns_opt_record([%{type: :opt} = p]) do
    IO.write """
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: #{p.version}, flags:#{dnssec(p.dnssec)}; udp: #{p.payload_size}
    """

    disp_edns_options(p.rdata)
  end

  defp dnssec(0), do: ""
  defp dnssec(1), do: " do"

  def disp_ends_options([]), do: nil

  defp disp_edns_options(options) do
    options
    |> Enum.each(fn n -> disp_edns_option_item(n) end)
  end

  defp disp_edns_option_item(%{code: :edns_client_subnet} = opt) do
    IO.puts """
    ; EDNS: ECS: #{complete_addr(opt)}/#{opt.source}, #{opt.scope}
    """
  end

  defp disp_edns_option_item(opt) do
    IO.inspect opt
  end

  def complete_addr(%{family: 1, source: source} = opt) do
    padding_length = 32 - source
    <<a1::8,a2::8,a3::8,a4::8>> = opt.addr <> <<0::size(padding_length)>>
    "#{:inet.ntoa({a1, a2, a3, a4})}"
  end

  def complete_addr(%{family: 2, source: source} = opt) do
    padding_length = 128 - source
    <<a1::16,a2::16,a3::16,a4::16,a5::16,a6::16,a7::16,a8::16>> = opt.addr <> <<0::size(padding_length)>>
    "#{:inet.ntoa({a1,a2,a3,a4,a5,a6,a7,a8})}"
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
  
  def disp_answer(p, part, is_sort) do
    IO.puts ";; #{a2s(part)} SECTION:"

    p[part]
    |> sort_answer(is_sort)
    |> Enum.map(fn n-> answer_item_to_string(n) end)
    |> Enum.each(fn n -> IO.write(n) end)

    IO.puts ""
    p
  end

  def sort_answer(p, true) do
    Enum.sort(p, fn x, y -> x.type < y.type end)
  end

  def sort_answer(p, _), do: p

  # Do not display OPT item in answer
  def answer_item_to_string(%{type: :opt}), do: ""

  def answer_item_to_string(a) do """
    #{a.name}		#{a.ttl}	#{a.class|>a2s}	#{a.type|>a2s}	#{a.rdata|>rdata_to_string(a.type)}
    """
  end

  def rdata_to_string(rdata, :a), do: :inet.ntoa(rdata.addr)
  def rdata_to_string(rdata, :aaaa), do: :inet.ntoa(rdata.addr)
  def rdata_to_string(rdata, :ns), do: rdata.name
  def rdata_to_string(rdata, :ptr), do: rdata.name
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
