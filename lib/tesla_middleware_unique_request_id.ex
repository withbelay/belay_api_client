defmodule Tesla.Middleware.UniqueRequestId do
  @moduledoc """
  Middleware to add a unique request id to the request headers if one is not already present.

  Adds the request id to the Logger metadata.
  """
  alias Tesla
  require Logger

  @behaviour Tesla.Middleware
  @header_name "x-request-id"

  @impl true
  def call(env, next, opts) do
    env
    |> add_unique_request_id(opts)
    |> Tesla.run(next)
  end

  defp add_unique_request_id(env, _opts) do
    case Tesla.get_header(env, @header_name) do
      nil ->
        request_id = generate_request_id()
        Logger.metadata(tesla_request_id: request_id)
        Tesla.put_header(env, @header_name, request_id)

      _id ->
        env
    end
  end

  def generate_request_id() do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end
end
