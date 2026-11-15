defmodule Doris.ChatRequest do
  @moduledoc "Validated view of the proxy's `POST /v1/chat/completions` body."

  @enforce_keys [:user_id, :conversation_id, :content]
  defstruct [:user_id, :conversation_id, :content, profile: %{}]

  @doc """
  `content` is the current user message content exactly as received (string or list of
  `text`/`image_url` parts), so images reach the vision model untouched.
  """
  def parse(%{
        "user" => user,
        "messages" => messages,
        "metadata" => %{"conversation_id" => cid} = meta
      })
      when is_binary(user) and user != "" and is_binary(cid) and cid != "" and is_list(messages) do
    case Enum.filter(messages, &match?(%{"role" => "user"}, &1)) |> List.last() do
      %{"content" => content} when is_binary(content) or is_list(content) ->
        {:ok,
         %__MODULE__{
           user_id: user,
           conversation_id: cid,
           content: content,
           profile: Map.get(meta, "profile") || %{}
         }}

      _ ->
        {:error, "messages must contain a user message"}
    end
  end

  def parse(_), do: {:error, "user, messages and metadata.conversation_id are required"}

  @doc "Concatenated text parts of the message (images ignored)."
  def text(%__MODULE__{content: content}) when is_binary(content), do: content

  def text(%__MODULE__{content: parts}) do
    parts
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => t} -> [t]
      _ -> []
    end)
    |> Enum.join("\n")
  end
end
