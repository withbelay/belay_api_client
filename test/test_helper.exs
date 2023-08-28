# Increase assert_receive timeout for all tests since smoke and integration tests may take longer
ExUnit.configure(assert_receive_timeout: 1_000)

ExUnit.start(exclude: [integration: true, smoke: true])
