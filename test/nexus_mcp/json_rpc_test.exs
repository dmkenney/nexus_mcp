defmodule NexusMCP.JsonRpcTest do
  use ExUnit.Case, async: true

  alias NexusMCP.JsonRpc

  describe "decode/1" do
    test "decodes a valid request" do
      msg = %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1, "params" => %{}}
      assert {:ok, %{method: "tools/list", id: 1, params: %{}}} = JsonRpc.decode(msg)
    end

    test "decodes a notification (no id)" do
      msg = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      assert {:ok, %{method: "notifications/initialized", id: nil, params: %{}}} =
               JsonRpc.decode(msg)
    end

    test "defaults params to empty map" do
      msg = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}
      assert {:ok, %{params: %{}}} = JsonRpc.decode(msg)
    end

    test "returns error for missing method" do
      msg = %{"jsonrpc" => "2.0", "id" => 1}
      assert {:error, %{"error" => %{"code" => -32600}}} = JsonRpc.decode(msg)
    end

    test "returns error for missing jsonrpc version" do
      msg = %{"method" => "ping", "id" => 1}
      assert {:error, %{"error" => %{"code" => -32600}}} = JsonRpc.decode(msg)
    end

    test "returns error for non-map input" do
      assert {:error, %{"error" => %{"code" => -32700}}} = JsonRpc.decode("not a map")
    end
  end

  describe "notification?/1" do
    test "true when id is nil" do
      assert JsonRpc.notification?(%{id: nil})
    end

    test "false when id is present" do
      refute JsonRpc.notification?(%{id: 1})
    end
  end

  describe "result/2" do
    test "builds a result response" do
      resp = JsonRpc.result(1, %{"tools" => []})
      assert resp == %{"jsonrpc" => "2.0", "id" => 1, "result" => %{"tools" => []}}
    end
  end

  describe "error/3" do
    test "builds an error response" do
      resp = JsonRpc.error(1, -32601, "Method not found")

      assert resp == %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "error" => %{"code" => -32601, "message" => "Method not found"}
             }
    end

    test "includes data when provided" do
      resp = JsonRpc.error(1, -32603, "Internal error", %{"detail" => "oops"})
      assert resp["error"]["data"] == %{"detail" => "oops"}
    end
  end
end
