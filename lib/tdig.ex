defmodule Tdig do
  @moduledoc """
  Documentation for `Tdig`.
  """

  @type dns_query_args :: %{
    name: String.t(),
    type: atom(),
    class: atom(),
    server: String.t(),
    port: integer(),
    tcp: boolean(),
    v4: boolean(),
    v6: boolean(),
    edns: boolean(),
    bufsize: integer(),
    options: list(),
    ex_rcode: integer(),
    write: String.t() | nil,
    write_request: String.t() | nil,
    read: String.t() | nil,
    sort: boolean(),
    ignore: boolean()
  }

  @spec resolve(dns_query_args()) :: :ok
  def resolve(arg) do
    start = System.monotonic_time(:millisecond)
    
    arg
    |> get_response
    |> write_file(arg.write)
    |> disp_response(arg, System.monotonic_time(:millisecond) - start)
  end

  @spec get_response(dns_query_args()) :: {binary(), {{integer(), integer(), integer(), integer()}, String.t()}}
  def get_response(%{read: file}) when is_binary(file),
    do: {File.read!(file), {{0, 0, 0, 0}, "  '#{file}'  "}}

  def get_response(arg) do
    %DNSpacket{
      id: :rand.uniform(0xffff),
      rd: 1,
      question: [
        %{
          qname: arg.name,
          qtype: arg.type,
          qclass: arg.class,
        }
      ],
      additional: check_edns(arg),
    }
    |> DNSpacket.create
    |> write_file(arg.write_request)
    |> send_server(arg)
  end

  @spec check_edns(map()) :: list()
  def check_edns(%{edns: false}), do: []

  def check_edns(arg) do
    [
      %{
        name: "",
        type: :opt,
        payload_size: arg.bufsize,
        ex_rcode: arg.ex_rcode,
        version: 0,
        dnssec: 0,
        z: 0,
        rdata: arg.options,
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

  @spec select_protocol(boolean(), boolean()) :: {:inet | :inet6, 4 | 6}
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

  defp qr(0), do: "  "
  defp qr(1), do: "qr"

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
    ;; ->>HEADER<<- opcode: #{opcode(p.opcode)}, status: #{DNS.rcode_text[DNS.rcode(p.rcode)]}, id: #{p.id}
    ;; flags:#{qr(p.qr)}#{aa(p.aa)}#{tc(p.tc)}#{rd(p.rd)}#{ra(p.rd)}#{z(p.z)}; QUERY: #{length(p.question)}, ANSWER #{length(p.answer)}, AUTHORITY: #{length(p.authority)}, ADDITIONAL: #{length(p.additional)}
    """

    p
  end

  @spec a2s(atom()) :: String.t()
  def a2s(a) do
    a
    |> Atom.to_string
    |> String.upcase
  end

  def disp_edns_pseudo_header(p) do
    disp_edns_opt_record(p.edns_info)

    p
  end
  
  def disp_edns_opt_record(nil), do: nil

  def disp_edns_opt_record(edns_info) when is_map(edns_info) do
    IO.write """
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: #{edns_info.version}, flags:#{dnssec(edns_info.dnssec)}; udp: #{edns_info.payload_size}
    """

    if Map.has_key?(edns_info, :ecs_family) do
      IO.puts """
      ; EDNS: ECS: #{format_ecs_subnet(edns_info.ecs_subnet)}/#{edns_info.ecs_source_prefix}, #{edns_info.ecs_scope_prefix}
    """
    end
  end

  defp dnssec(0), do: ""
  defp dnssec(1), do: " do"

  # Format ECS subnet with proper error handling
  defp format_ecs_subnet(subnet) when is_tuple(subnet) and tuple_size(subnet) in [4, 8] do
    :inet.ntoa(subnet) |> to_string()
  end

  defp format_ecs_subnet(subnet) when is_binary(subnet), do: subnet
  defp format_ecs_subnet(subnet) when is_list(subnet), do: to_string(subnet)
  defp format_ecs_subnet(_), do: "invalid"


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

    case part do
      :answer -> p.answer
      :authority -> p.authority
      :additional -> p.additional
    end
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
    # Get system local time using NaiveDateTime (OS-independent, cleaner)
    now = NaiveDateTime.local_now() |> NaiveDateTime.to_string()

    IO.puts """
    ;; Query time: #{time} ms
    ;; SERVER: #{server}##{port}(#{server})
    ;; WHEN: #{now}
    ;; MSG SIZE rcvd: #{size}
    """
  end
end
