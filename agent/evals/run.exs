# Black-box E2E runner. Talks only to the proxy's public POST /chat and, for verification,
# GET /admin/log (allowed here: this is the evaluator, not the agent runtime).
#
#   docker compose --profile test run --rm agent-test mix run --no-start evals/run.exs evals/scenarios.json
#   docker compose --profile eval up -d proxy-faults agent-eval
#   docker compose --profile test run --rm agent-test mix run --no-start evals/run.exs evals/faults.json
#
# Writes evals/reports/<suite>-<timestamp>.{json,md} and <suite>-latest.{json,md}.
Application.ensure_all_started(:req)

defmodule Eval do
  @tools_ok ~w(search_by_text garment_creation tryon avatar looks wardrobe show_artifact)

  def main([path | _]) do
    spec = path |> File.read!() |> Jason.decode!()
    target = System.get_env("EVAL_TARGET", spec["target"])
    run = Integer.to_string(System.os_time(:second))
    started = DateTime.utc_now()

    results = Enum.map(spec["scenarios"], &run_scenario(&1, target, run))
    report = report(spec, target, started, results)
    write(spec["suite"], report)
    IO.puts(markdown(report))
    if Enum.all?(results, &(&1.status == "passed")), do: :ok, else: System.halt(1)
  end

  # ── execution ──────────────────────────────────────────────────────────────

  defp run_scenario(scenario, target, run) do
    IO.puts(:stderr, "▶ #{scenario["id"]}")
    convs = %{}

    {turns, _} =
      Enum.map_reduce(scenario["turns"], convs, fn turn, convs ->
        key = turn["conversation"]
        conv = Map.get_lazy(convs, key, fn -> "eval-#{scenario["id"]}-#{key}-#{run}" end)
        user = String.replace(turn["user"], "{run}", run)
        {run_turn(target, user, conv, turn), Map.put(convs, key, conv)}
      end)

    failures =
      Enum.flat_map(Enum.with_index(turns, 1), fn {t, i} ->
        Enum.map(t.failures, &"turno #{i}: #{&1}")
      end)

    %{
      id: scenario["id"],
      title: scenario["title"],
      status: if(failures == [], do: "passed", else: "failed"),
      failures: failures,
      latency_ms: Enum.sum(Enum.map(turns, & &1.latency_ms)),
      turns: turns
    }
  end

  defp run_turn(target, user, conv, turn) do
    t0 = System.monotonic_time(:millisecond)

    events =
      case Req.post(target <> "/chat",
             json: %{user_id: user, conversation_id: conv, message: turn["message"]},
             receive_timeout: 115_000,
             retry: false
           ) do
        {:ok, %{status: 200, body: body}} ->
          parse_sse(body)

        {:ok, %{status: s, body: b}} ->
          [%{"type" => "error", "message" => "HTTP #{s}: #{inspect(b)}"}]

        {:error, e} ->
          [%{"type" => "error", "message" => Exception.message(e)}]
      end

    latency = System.monotonic_time(:millisecond) - t0
    log = admin_turn(target, conv, turn["message"])
    calls = (log && log["calls"]) || []

    obs = %{
      user: user,
      conversation_id: conv,
      message: turn["message"],
      text: events |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join(& &1["delta"]),
      artifacts: for(%{"type" => "artifact", "artifact" => a} <- events, do: a),
      feedback_states: for(%{"type" => "feedback", "state" => s} <- events, do: s),
      errors: for(%{"type" => "error"} = e <- events, do: e["message"] || e["code"]),
      outcome: log && log["outcome"],
      latency_ms: latency,
      proxy_duration_ms: log && log["duration_ms"],
      tool_calls:
        Enum.map(calls, fn c ->
          %{
            tool: c["tool"],
            status: c["status"],
            error_code: c["error_code"],
            request: c["request"],
            response: c["response"]
          }
        end)
    }

    Map.put(Map.drop(obs, []), :failures, check(obs, turn["expect"] || %{}))
    |> Map.update!(:tool_calls, fn cs -> Enum.map(cs, &Map.drop(&1, [:response])) end)
  end

  defp parse_sse(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.flat_map(fn
      "data: " <> json ->
        case Jason.decode(json),
          do: (
            {:ok, e} -> [e]
            _ -> []
          )

      _ ->
        []
    end)
  end

  defp admin_turn(target, conv, message) do
    case Req.get(target <> "/admin/log", params: [conversation_id: conv], retry: false) do
      {:ok, %{status: 200, body: %{"turns" => turns}}} ->
        turns |> Enum.filter(&(&1["message"] == message)) |> List.last()

      _ ->
        nil
    end
  end

  # ── assertions ─────────────────────────────────────────────────────────────

  defp check(obs, expect) do
    names = Enum.map(obs.tool_calls, & &1.tool)
    products = for %{"kind" => "PRODUCT"} = a <- obs.artifacts, do: a

    invariants(obs) ++
      Enum.flat_map(expect, fn
        {"tools_required", ts} ->
          for t <- ts, t not in names, do: "tool #{t} não foi chamada"

        {"tools_forbidden", ts} ->
          for t <- ts, t in names, do: "tool proibida #{t} foi chamada"

        {"artifact_kinds_required", ks} ->
          for k <- ks, not Enum.any?(obs.artifacts, &(&1["kind"] == k)), do: "nenhum card #{k}"

        {"artifacts_min", n} ->
          if length(obs.artifacts) < n, do: ["#{length(obs.artifacts)} cards (< #{n})"], else: []

        {"artifacts_max", n} ->
          if length(obs.artifacts) > n, do: ["#{length(obs.artifacts)} cards (> #{n})"], else: []

        {"max_price", max} ->
          for p <- products,
              p["price"] > max,
              do: "card #{p["item_id"]} R$#{p["price"]} acima de R$#{max}"

        {"forbidden_products", ids} ->
          for p <- products, p["item_id"] in ids, do: "produto proibido #{p["item_id"]} mostrado"

        {"products_required", ids} ->
          for id <- ids,
              not Enum.any?(products, &(&1["item_id"] == id)),
              do: "produto #{id} não mostrado"

        {"forbidden_artifact_terms", re} ->
          for a <- obs.artifacts,
              artifact_text(a) =~ ~r/#{re}/iu,
              do: "card com termo proibido: #{artifact_text(a)}"

        {"garment_items", ids} ->
          garment_items(obs, ids)

        {"min_calls", m} ->
          for {t, n} <- m, Enum.count(names, &(&1 == t)) < n, do: "#{t} chamada menos de #{n}x"

        {"max_calls", m} ->
          for {t, n} <- m, Enum.count(names, &(&1 == t)) > n, do: "#{t} chamada mais de #{n}x"

        {"feedback_error", true} ->
          if "error" in obs.feedback_states, do: [], else: ["nenhum feedback de erro"]

        {"outcome", o} ->
          if obs.outcome == o, do: [], else: ["outcome #{inspect(obs.outcome)} ≠ #{o}"]

        {"latency_max_ms", ms} ->
          if obs.latency_ms > ms, do: ["latência #{obs.latency_ms} ms > #{ms}"], else: []

        {"text_must_match" <> _, re} ->
          if obs.text =~ ~r/#{re}/iu, do: [], else: ["texto não casa /#{re}/"]

        {"text_must_not_match", re} ->
          if obs.text =~ ~r/#{re}/iu, do: ["texto casa /#{re}/ (proibido)"], else: []
      end)
  end

  # Checked on every turn.
  defp invariants(obs) do
    calls = obs.tool_calls

    [
      obs.errors != [] && "erro no stream: #{Enum.join(obs.errors, "; ")}",
      obs.outcome not in [nil, "done"] && "outcome do proxy: #{obs.outcome}",
      Enum.any?(calls, &(&1.tool not in @tools_ok)) && "tool desconhecida chamada",
      Enum.any?(calls, &(&1.tool == "tryon" and length(&1.request["garment_ids"] || []) > 1)) &&
        "tryon com mais de 1 peça",
      orphan_tryon(calls),
      retried_permanent(calls),
      unknown_shown_product(calls)
    ]
    |> Enum.filter(& &1)
  end

  defp orphan_tryon(calls) do
    shown =
      for %{tool: "show_artifact", request: %{"type" => "TRYON_CARD", "value" => v}} <- calls,
          do: v

    orphans =
      for %{tool: "tryon", status: 200, response: %{"data" => d}} <- calls,
          d["tryon_id"] not in shown and d["look_id"] not in shown,
          do: d["tryon_id"]

    orphans != [] && "try-on gerado e não mostrado: #{Enum.join(orphans, ",")}"
  end

  defp retried_permanent(calls) do
    calls
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] ->
      a.tool == b.tool and a.request == b.request and a.status >= 400 and
        get_in(a.response || %{}, ["error", "retryable"]) == false
    end) && "erro retryable=false foi repetido"
  end

  # Products shown in this turn must come from a search in this turn, or (multi-turn) from
  # an earlier one; we only flag ids never seen in any search response of this turn when
  # the turn did search.
  defp unknown_shown_product(calls) do
    searched =
      for %{tool: "search_by_text", response: %{"data" => %{"products" => ps}}} <- calls,
          p <- ps,
          do: p["search_item_id"]

    shown =
      for %{tool: "show_artifact", request: %{"type" => "PRODUCT", "value" => v}} <- calls, do: v

    unknown = if searched == [], do: [], else: shown -- searched
    unknown != [] && "PRODUCT mostrado sem vir da busca: #{Enum.join(unknown, ",")}"
  end

  defp garment_items(obs, ids) do
    created =
      for %{tool: "garment_creation", request: %{"search_item_id" => id}} <- obs.tool_calls,
          do: id

    if Enum.sort(Enum.uniq(created)) == Enum.sort(ids),
      do: [],
      else: ["garment_creation em #{inspect(created)}, esperado #{inspect(ids)}"]
  end

  defp artifact_text(a), do: "#{a["name"]} #{Enum.join(a["tags"] || [], " ")}"

  # ── report ─────────────────────────────────────────────────────────────────

  defp report(spec, target, started, results) do
    latencies = results |> Enum.flat_map(& &1.turns) |> Enum.map(& &1.latency_ms) |> Enum.sort()

    %{
      suite: spec["suite"],
      target: target,
      memory_mode: System.get_env("MEMORY_MODE", "v1 (padrão do agente)"),
      model: System.get_env("AGENT_MODEL", "openai/gpt-6-luna (padrão do agente)"),
      started_at: DateTime.to_iso8601(started),
      finished_at: DateTime.to_iso8601(DateTime.utc_now()),
      summary: %{
        passed: Enum.count(results, &(&1.status == "passed")),
        failed: Enum.count(results, &(&1.status == "failed")),
        total: length(results),
        turns: length(latencies),
        p50_ms: percentile(latencies, 50),
        p95_ms: percentile(latencies, 95)
      },
      scenarios: results
    }
  end

  defp percentile([], _), do: nil
  defp percentile(sorted, p), do: Enum.at(sorted, max(ceil(p / 100 * length(sorted)) - 1, 0))

  defp write(suite, report) do
    dir = Path.join(__DIR__, "reports")
    File.mkdir_p!(dir)
    stamp = report.started_at |> String.replace(~r/[:.]/, "-") |> String.slice(0, 19)

    for name <- ["#{suite}-#{stamp}", "#{suite}-latest"] do
      File.write!(Path.join(dir, name <> ".json"), Jason.encode_to_iodata!(report, pretty: true))
      File.write!(Path.join(dir, name <> ".md"), markdown(report))
    end
  end

  defp markdown(r) do
    s = r.summary

    rows =
      Enum.map(r.scenarios, fn sc ->
        tools =
          sc.turns
          |> Enum.map(fn t -> Enum.map_join(t.tool_calls, "→", & &1.tool) end)
          |> Enum.join(" ‖ ")

        cards = sc.turns |> Enum.flat_map(& &1.artifacts) |> Enum.map_join(", ", &card/1)

        "| #{sc.id} | #{sc.status} | #{sc.latency_ms} | #{blank(tools)} | #{blank(cards)} | #{blank(Enum.join(sc.failures, "; "))} |"
      end)

    details =
      Enum.map(r.scenarios, fn sc ->
        turns =
          Enum.map(sc.turns, fn t ->
            "- `#{t.user}` / `#{t.conversation_id}` — \"#{t.message}\" (#{t.latency_ms} ms, outcome #{t.outcome})\n  - resposta: #{String.replace(t.text, "\n", " ")}"
          end)

        "### #{sc.id} — #{sc.title}\n" <> Enum.join(turns, "\n")
      end)

    """
    # Relatório E2E — #{r.suite}

    - Alvo: #{r.target} · memória: #{r.memory_mode} · modelo: #{r.model}
    - Início: #{r.started_at} · fim: #{r.finished_at}
    - Resultado: **#{s.passed}/#{s.total} passaram**, #{s.failed} falharam · #{s.turns} turnos · p50 #{s.p50_ms} ms · p95 #{s.p95_ms} ms (amostra pequena, não generalizar)

    | Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
    | --- | --- | --- | --- | --- | --- |
    #{Enum.join(rows, "\n")}

    ## Turnos

    #{Enum.join(details, "\n\n")}
    """
  end

  defp card(%{"kind" => "PRODUCT"} = a), do: "PRODUCT #{a["item_id"]} R$#{a["price"]}"

  defp card(%{"kind" => k} = a),
    do: "#{k} #{a["item_id"] || String.slice(a["tryon_id"] || a["garment_id"] || "", 0, 8)}"

  defp blank(""), do: "—"
  defp blank(s), do: String.replace(s, "|", "/")
end

Eval.main(System.argv())
