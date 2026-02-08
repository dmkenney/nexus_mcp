defmodule NexusMCP.Server.Schema do
  @moduledoc """
  Converts param type DSL definitions to JSON Schema.

  ## Type DSL

      :string              → optional string
      :string!             → required string
      :integer             → optional integer
      :boolean             → optional boolean
      :number              → optional number
      :object              → optional object
      {:string!, "desc"}   → required string with description
      {:array, :string}    → array of strings
      {{:array, :string}, "Tags"} → array with description
  """

  @type param_type ::
          :string
          | :string!
          | :integer
          | :integer!
          | :boolean
          | :boolean!
          | :number
          | :number!
          | :object
          | :object!
          | {:array, atom()}
          | {param_type(), String.t()}

  @doc """
  Converts a keyword list of param definitions to a JSON Schema object.

  ## Example

      iex> params_to_schema([name: :string!, id: {:string!, "Page ID"}])
      %{
        type: "object",
        properties: %{
          "name" => %{type: "string"},
          "id" => %{type: "string", description: "Page ID"}
        },
        required: ["name", "id"]
      }
  """
  @spec params_to_schema(keyword()) :: map()
  def params_to_schema(params) when is_list(params) do
    {properties, required} =
      Enum.reduce(params, {%{}, []}, fn {name, type_spec}, {props, req} ->
        {schema, is_required} = type_to_schema(type_spec)
        name_str = to_string(name)
        props = Map.put(props, name_str, schema)
        req = if is_required, do: [name_str | req], else: req
        {props, req}
      end)

    schema = %{type: "object", properties: properties}

    case Enum.reverse(required) do
      [] -> schema
      req -> Map.put(schema, :required, req)
    end
  end

  @doc """
  Converts a single type spec to `{json_schema_map, is_required}`.
  """
  @spec type_to_schema(param_type()) :: {map(), boolean()}
  def type_to_schema({type_spec, description}) when is_binary(description) do
    {schema, required} = type_to_schema(type_spec)
    {Map.put(schema, :description, description), required}
  end

  def type_to_schema({:array, item_type}) do
    {item_schema, _} = type_to_schema(item_type)
    {%{type: "array", items: item_schema}, false}
  end

  def type_to_schema({:array!, item_type}) do
    {item_schema, _} = type_to_schema(item_type)
    {%{type: "array", items: item_schema}, true}
  end

  def type_to_schema(:string), do: {%{type: "string"}, false}
  def type_to_schema(:string!), do: {%{type: "string"}, true}
  def type_to_schema(:integer), do: {%{type: "integer"}, false}
  def type_to_schema(:integer!), do: {%{type: "integer"}, true}
  def type_to_schema(:boolean), do: {%{type: "boolean"}, false}
  def type_to_schema(:boolean!), do: {%{type: "boolean"}, true}
  def type_to_schema(:number), do: {%{type: "number"}, false}
  def type_to_schema(:number!), do: {%{type: "number"}, true}
  def type_to_schema(:object), do: {%{type: "object"}, false}
  def type_to_schema(:object!), do: {%{type: "object"}, true}

  @doc """
  Strips `!` from all param types, making everything optional.
  Useful for update schemas where all fields should be optional.
  """
  @spec make_optional(keyword()) :: keyword()
  def make_optional(params) when is_list(params) do
    Enum.map(params, fn {name, type_spec} ->
      {name, strip_required(type_spec)}
    end)
  end

  defp strip_required({type_spec, description}) when is_binary(description) do
    {strip_required(type_spec), description}
  end

  defp strip_required({:array!, item_type}), do: {:array, item_type}
  defp strip_required(:string!), do: :string
  defp strip_required(:integer!), do: :integer
  defp strip_required(:boolean!), do: :boolean
  defp strip_required(:number!), do: :number
  defp strip_required(:object!), do: :object
  defp strip_required(other), do: other
end
