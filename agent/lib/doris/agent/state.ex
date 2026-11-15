defmodule Doris.Agent.State do
  @moduledoc """
  Per-turn state threaded through the agent loop.

  `known` is the allowlist: every id the model may use must have been returned by a proxy
  tool in this conversation (this turn, or a previous turn loaded from history). Products
  keep their search data so price/colour rules can be re-checked before showing them.
  """
  alias Doris.ChatRequest

  defstruct [
    :conversation_id,
    :user_id,
    :deadline,
    :emit,
    products: %{},
    garments: MapSet.new(),
    tryons: MapSet.new(),
    looks: MapSet.new(),
    # garment_id => search_item_id, to show the product card when a try-on fails
    garment_products: %{},
    max_price: nil,
    avoid_colors: [],
    feedback_seq: 0,
    shown: MapSet.new(),
    extra_messages: []
  ]

  def new(%ChatRequest{} = req, emit, opts \\ []) do
    budget_ms =
      Keyword.get(opts, :budget_ms, Application.get_env(:doris, :turn_budget_ms, 80_000))

    %__MODULE__{
      conversation_id: req.conversation_id,
      user_id: req.user_id,
      emit: emit,
      deadline: System.monotonic_time(:millisecond) + budget_ms
    }
  end

  def remaining_ms(%__MODULE__{deadline: d}), do: d - System.monotonic_time(:millisecond)

  def add_products(state, products) do
    %{
      state
      | products: Enum.reduce(products, state.products, &Map.put(&2, &1["search_item_id"], &1))
    }
  end

  def add_garment(state, garment_id, product_id \\ nil) do
    state = %{state | garments: MapSet.put(state.garments, garment_id)}

    if product_id,
      do: %{state | garment_products: Map.put(state.garment_products, garment_id, product_id)},
      else: state
  end

  def add_tryon(state, ids), do: %{state | tryons: Enum.into(ids, state.tryons)}
  def add_looks(state, ids), do: %{state | looks: Enum.into(ids, state.looks)}

  def known_product?(state, id), do: Map.has_key?(state.products, id)
  def known_garment?(state, id), do: MapSet.member?(state.garments, id)

  def known_tryon?(state, id),
    do: MapSet.member?(state.tryons, id) or MapSet.member?(state.looks, id)

  @doc "Returns a feedback id like `tryon-2` and the updated state."
  def next_feedback_id(state, prefix) do
    seq = state.feedback_seq + 1
    {"#{prefix}-#{seq}", %{state | feedback_seq: seq}}
  end
end
