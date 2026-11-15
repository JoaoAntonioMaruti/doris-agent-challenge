import Config

# The agent is only reached over the internal compose network (plain HTTP), so no force_ssl.

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
