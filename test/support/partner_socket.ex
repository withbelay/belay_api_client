defmodule BelayApiClient.PartnerSocket do
  @moduledoc """
  A Slipstream powered websocket client
  """

  use Slipstream

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    host = Keyword.fetch!(opts, :host)
    token = Keyword.fetch!(opts, :token)
    partner_id = Keyword.fetch!(opts, :partner_id)
    stock_universe = Keyword.fetch!(opts, :stock_universe)

    Slipstream.start_link(
      __MODULE__,
      [uri: "#{host}/partner/websocket?token=#{token}", stock_universe: stock_universe, test_pid: test_pid, partner_id: partner_id],
      name: __MODULE__
    )
  end

  @impl true
  def init(uri: uri, stock_universe: stock_universe, test_pid: test_pid, partner_id: partner_id) do
    socket =
      [uri: uri]
      |> connect!()
      |> assign(:test_pid, test_pid)
      |> assign(:partner_id, partner_id)

    {:ok, socket, {:continue, {:await_connection, stock_universe}}}
  end

  @impl true
  def handle_message(topic, event, message, socket) do
    send(socket.assigns.test_pid, {topic, event, message})
    {:ok, socket}
  end

  @impl true
  def handle_join(topic, join_response, socket) do
    send(socket.assigns.test_pid, {topic, :joined, join_response})
    {:ok, socket}
  end

  @impl true
  def handle_continue({:await_connection, stock_universe}, socket) do
    socket =
      case await_connect(socket) do
        {:ok, socket} ->
          socket =
            Enum.reduce(stock_universe, socket, fn sym, socket ->
              join(socket, "offerings:#{socket.assigns.partner_id}:#{sym}")
            end)

            join(socket, "policy_updates:#{socket.assigns.partner_id}")

        {:error, reason} ->
          Logger.critical("Couldn't connect to Belay: #{inspect(reason)}")
          socket
      end

    {:noreply, socket}
  end

  @impl Slipstream
  def terminate(_reason, socket) do
    disconnect(socket)
  end
end
