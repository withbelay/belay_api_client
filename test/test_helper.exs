# Increase assert_receive timeout for all tests since smoke and integration tests may take longer
ExUnit.configure(assert_receive_timeout: 5_000)

current_time = Time.utc_now()
is_smoke = :smoke in ExUnit.configuration()[:include]

cond do
  is_smoke and Time.after?(current_time, ~T[14:30:00]) and Time.before?(current_time, ~T[21:00:00]) ->
    ExUnit.start(include: [smoke_open_hours: true])

  is_smoke ->
    ExUnit.start(include: [smoke_closed_hours: true])

  true ->
    ExUnit.start(exclude: [integration: true, smoke_open_hours: true, smoke_closed_hours: true])
end
