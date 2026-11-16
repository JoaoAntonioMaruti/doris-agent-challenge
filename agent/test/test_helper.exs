# Memory extraction gets its own model id in tests so LLM stubs can tell the calls apart.
Application.put_env(
  :doris,
  :models,
  Keyword.put(Application.fetch_env!(:doris, :models), :memory, "test/memory-model")
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Doris.Repo, :manual)
