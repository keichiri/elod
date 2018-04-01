defmodule Storage.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, [base]) do
    Storage.Supervisor.start_link(base)
  end
end
