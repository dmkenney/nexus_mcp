defmodule NexusMCP.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 encode/decode utilities.

  Pure functions for parsing incoming requests and building responses.
  """

  # Error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  def parse_error_code, do: @parse_error
  def invalid_request_code, do: @invalid_request
  def method_not_found_code, do: @method_not_found
  def invalid_params_code, do: @invalid_params
  def internal_error_code, do: @internal_error

  @doc """
  Decode a JSON-RPC 2.0 request from parsed body params (map).

  Returns `{:ok, request}` or `{:error, response}`.
  """
  def decode(%{"jsonrpc" => "2.0", "method" => method} = msg) when is_binary(method) do
    {:ok,
     %{
       method: method,
       id: Map.get(msg, "id"),
       params: Map.get(msg, "params", %{})
     }}
  end

  def decode(%{} = _msg) do
    {:error, error(nil, @invalid_request, "Invalid Request")}
  end

  def decode(_) do
    {:error, error(nil, @parse_error, "Parse error")}
  end

  @doc """
  Returns true if the request is a notification (no id field).
  """
  def notification?(%{id: nil}), do: true
  def notification?(%{id: _}), do: false

  @doc """
  Build a successful JSON-RPC 2.0 response.
  """
  def result(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  @doc """
  Build a JSON-RPC 2.0 error response.
  """
  def error(id, code, message, data \\ nil) do
    error_obj = %{"code" => code, "message" => message}
    error_obj = if data, do: Map.put(error_obj, "data", data), else: error_obj

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => error_obj
    }
  end
end
