defmodule Doris.History do
  @moduledoc """
  Persistent conversation history (users, conversations, messages, tool_executions).

    * `open/3` claims a conversation for a user; another user reusing the id is rejected.
    * `context/1` rebuilds the model context without splitting tool_call/tool pairs.
    * `allowlist/2` rebuilds the ids a conversation may use from recorded tool results.
    * `save_turn/3` stores the turn's messages and tool executions in one transaction.
  """
  import Ecto.Query
  alias Doris.Repo
  alias Doris.Agent.State
  alias Doris.History.{Conversation, Message, ToolExecution, User}

  @context_messages 40

  @spec open(String.t(), String.t(), map()) :: :ok | {:error, :conversation_owned}
  def open(user_id, conversation_id, profile \\ %{}) do
    now = DateTime.utc_now()

    Repo.insert!(%User{id: user_id, profile: profile || %{}},
      on_conflict: [set: [profile: profile || %{}, updated_at: now]],
      conflict_target: :id
    )

    Repo.insert!(
      %Conversation{id: conversation_id, user_id: user_id, started_at: now, updated_at: now},
      on_conflict: :nothing,
      conflict_target: :id
    )

    # the owner is whoever inserted first; it never changes
    case Repo.get!(Conversation, conversation_id) do
      %{user_id: ^user_id} -> :ok
      _other -> {:error, :conversation_owned}
    end
  end

  @doc """
  Last messages of the conversation in model format. The window always starts at a user
  message, so an assistant tool_calls message is never separated from its tool results.
  """
  def context(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(desc: :sequence)
    |> limit(@context_messages)
    |> select([m], m.content)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1["role"] != "user"))
  end

  @doc "Seeds the turn state with ids returned by the proxy in earlier turns of this conversation."
  def allowlist(%State{} = state, conversation_id) do
    ToolExecution
    |> where(conversation_id: ^conversation_id, status: "ok")
    |> order_by(:inserted_at)
    |> Repo.all()
    |> Enum.reduce(state, &remember/2)
  end

  defp remember(%{tool_name: "search_by_text", result: %{"products" => ps}}, state),
    do: State.add_products(state, ps)

  defp remember(
         %{tool_name: "garment_creation", arguments: args, result: %{"garment_id" => g}},
         state
       ),
       do: State.add_garment(state, g, args["search_item_id"])

  defp remember(%{tool_name: "wardrobe", result: %{"garments" => gs}}, state),
    do: Enum.reduce(gs, state, &State.add_garment(&2, &1["garment_id"]))

  defp remember(%{tool_name: "tryon", result: r}, state),
    do: State.add_tryon(state, Enum.reject([r["tryon_id"], r["look_id"]], &is_nil/1))

  defp remember(%{tool_name: "looks", result: %{"looks" => looks}}, state),
    do: State.add_looks(state, Enum.map(looks, & &1["look_id"]))

  defp remember(_execution, state), do: state

  @doc """
  Stores the turn atomically. `messages` are model-format maps (atom or string keys);
  `executions` are the proxy calls recorded during the turn.
  """
  def save_turn(conversation_id, messages, executions) do
    Repo.transaction(fn ->
      # row lock on the conversation serialises concurrent turns of the same conversation
      Repo.one!(from c in Conversation, where: c.id == ^conversation_id, lock: "FOR UPDATE")

      start =
        Repo.one(
          from m in Message, where: m.conversation_id == ^conversation_id, select: max(m.sequence)
        ) ||
          0

      now = DateTime.utc_now()

      messages
      |> Enum.map(&stringify/1)
      |> Enum.with_index(start + 1)
      |> Enum.each(fn {msg, seq} ->
        Repo.insert!(%Message{
          conversation_id: conversation_id,
          role: msg["role"],
          content: strip_inline_images(msg),
          tool_call_id: msg["tool_call_id"],
          sequence: seq
        })
      end)

      Enum.each(executions, fn e ->
        Repo.insert!(struct(ToolExecution, Map.put(e, :conversation_id, conversation_id)),
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(conversation_id, tool_call_id) WHERE tool_call_id IS NOT NULL"}
        )
      end)

      Repo.update_all(from(c in Conversation, where: c.id == ^conversation_id),
        set: [updated_at: now]
      )

      :ok
    end)
  end

  defp stringify(map), do: map |> Jason.encode!() |> Jason.decode!()

  # Attached photos arrive as base64 data URIs: keep a placeholder, never the bytes.
  # Public URLs (e.g. look images) are kept as a text reference only.
  defp strip_inline_images(%{"content" => parts} = msg) when is_list(parts) do
    %{msg | "content" => Enum.map(parts, &strip_part/1)}
  end

  defp strip_inline_images(msg), do: msg

  defp strip_part(%{"type" => "image_url", "image_url" => %{"url" => "data:" <> _}}),
    do: %{"type" => "text", "text" => "[imagem enviada pela pessoa em um turno anterior]"}

  defp strip_part(%{"type" => "image_url", "image_url" => %{"url" => url}}),
    do: %{"type" => "text", "text" => "[imagem: #{url}]"}

  defp strip_part(part), do: part
end
