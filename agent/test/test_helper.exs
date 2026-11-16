# Controller/runner tests use v1 (no embeddings stub needed); v2 is covered directly
# in Doris.Memory.SemanticTest.
Application.put_env(:doris, :memory_mode, :v1)

# Memory extraction gets its own model id in tests so LLM stubs can tell the calls apart.
Application.put_env(
  :doris,
  :models,
  Keyword.put(Application.fetch_env!(:doris, :models), :memory, "test/memory-model")
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Doris.Repo, :manual)
