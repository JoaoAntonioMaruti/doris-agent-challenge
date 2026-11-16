defmodule Doris.Memory.StructuredTest do
  use Doris.DataCase, async: true
  alias Doris.History
  alias Doris.Memory.{Preferences, Structured}

  defp extraction(json),
    do: Doris.LLMStub.stub(fn _, _ -> flunk("only memory calls expected") end, json)

  setup do
    :ok = History.open("u_ana__abc", "c-abc")
    :ok = History.open("u_ana__def", "c-def")
    :ok
  end

  test "saves extracted preferences and loads them as prompt + hard colour constraint" do
    extraction(
      ~s({"size":"M","add_disliked_colors":["Amarelo"],"add_styles":["minimalista"],"budget_max":null,"notes":null})
    )

    assert {:ok, %Preferences{version: 1}} =
             Structured.update("u_ana__abc", %{user_text: "Odeio amarelo, visto M…"})

    assert %{avoid_colors: ["amarelo"], prompt: prompt} = Structured.load("u_ana__abc", "")
    assert prompt =~ "Tamanho: M" and prompt =~ "minimalista"
  end

  test "users with different suffixes never share preferences" do
    extraction(~s({"add_disliked_colors":["amarelo"]}))
    {:ok, _} = Structured.update("u_ana__abc", %{user_text: "odeio amarelo"})
    assert %{avoid_colors: [], prompt: nil} = Structured.load("u_ana__def", "")
  end

  test "a later message keeps facts it does not mention and applies explicit corrections" do
    extraction(
      ~s({"size":"M","add_disliked_colors":["amarelo","laranja"],"add_styles":["minimalista"]})
    )

    {:ok, _} = Structured.update("u_ana__abc", %{user_text: "a"})

    extraction(~s({"size":"G","remove_disliked_colors":["amarelo"],"add_styles":[]}))

    {:ok, prefs} =
      Structured.update("u_ana__abc", %{user_text: "agora visto G e voltei a gostar de amarelo"})

    assert prefs.size == "G"
    assert prefs.disliked_colors == ["laranja"]
    assert prefs.preferred_styles == ["minimalista"]
    assert prefs.version == 2
  end

  test "nothing to extract leaves the profile untouched" do
    extraction(~s({"size":null,"add_disliked_colors":[],"notes":""}))
    assert :unchanged = Structured.update("u_ana__abc", %{user_text: "oi"})
    assert Structured.get("u_ana__abc").inserted_at == nil
  end

  test "invalid model output is an error and does not change the profile" do
    extraction("isso não é json")
    assert {:error, :invalid_json} = Structured.update("u_ana__abc", %{user_text: "x"})
  end

  test "parse drops wrongly typed and oversized values" do
    assert {:ok, %{size: "M"} = changes} =
             Structured.parse(
               ~s({"size":"M","add_disliked_colors":"amarelo","budget_max":"barato","notes":#{Jason.encode!(String.duplicate("a", 1000))}})
             )

    refute Map.has_key?(changes, :add_disliked_colors)
    refute Map.has_key?(changes, :budget_max)
    assert String.length(changes.notes) == 300
  end
end
