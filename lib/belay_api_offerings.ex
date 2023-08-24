defmodule BelayApiOfferings do
  @moduledoc """
  A Slipstream powered websocket client
  """

  use Slipstream

  require Logger

  @doc """
  Setup the ETS table for storing offerings so that closing the socket or process failure doesn't lose them
  """
  @spec setup() :: :ok
  def setup() do
    :ets.new(__MODULE__, [:set, :public, :named_table])
    :ets.insert(__MODULE__, {:status, :disconnected})
  end

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(host: host, token: token, stock_universe: stock_universe) do
    uri = "#{host}/partner/websocket?token=#{token}"

    Slipstream.start_link(__MODULE__, [uri: uri, stock_universe: stock_universe], name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {stock_universe, opts} = Keyword.pop!(opts, :stock_universe)
    {:ok, socket} = connect(opts)

    {:ok, socket, {:continue, {:await_connection, stock_universe}}}
  end

  def fetch_offerings(sym) do
    case :ets.lookup(__MODULE__, sym) do
      [{^sym, offerings}] -> offerings
      [] -> nil
    end
  rescue
    _ -> nil
  end

  def status() do
    [{:status, status}] = :ets.lookup(__MODULE__, :status)
    status
  end

  @doc """
  Close the socket connection and terminate the genserver
  """
  def close() do
    GenServer.cast(__MODULE__, :disconnect)
  end

  @impl true
  def handle_message("offerings:" <> sym, "offerings", %{"offerings" => offerings}, socket) do
    add_offerings(sym, offerings)

    {:ok, socket}
  end

  @impl true
  def handle_join("offerings:" <> sym, offerings, socket) do
    add_offerings(sym, offerings)
    :ets.insert(__MODULE__, {:status, :joined})

    {:ok, socket}
  end

  @impl true
  def handle_continue({:await_connection, stock_universe}, socket) do
    :ets.insert(__MODULE__, {:status, :awaiting_connection})

    socket =
      case await_connect(socket) do
        {:ok, socket} ->
          :ets.insert(__MODULE__, {:status, :connected})

          Enum.reduce(stock_universe, socket, fn sym, socket ->
            join(socket, "offerings:#{sym}")
          end)

        {:error, reason} ->
          :ets.insert(__MODULE__, {:status, :failed_to_connect})
          Logger.critical("[BelayApiOfferings] Couldn't connect to Belay: #{inspect(reason)}")
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_cast(:disconnect, socket) do
    :ets.insert(__MODULE__, {:status, :disconnected})
    {:stop, "Requested disconnect", socket}
  end

  @impl Slipstream
  def terminate(_reason, socket) do
    disconnect(socket)
  end

  defp add_offerings(sym, offerings) do
    IO.inspect(offerings, option: :pretty, label: "offerings; #{__ENV__.file}:#{__ENV__.line}")
    :ets.insert(__MODULE__, {sym, offerings})
  end
end
