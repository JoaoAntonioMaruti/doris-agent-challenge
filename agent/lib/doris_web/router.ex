defmodule DorisWeb.Router do
  use DorisWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DorisWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
