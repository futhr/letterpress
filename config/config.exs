import Config

config :letterpress,
  compiler_enabled: true,
  compiler_pool_size: 2,
  compiler_timeout: 15_000,
  compiler_max_frame_bytes: 2_000_000,
  render_timeout: 1_000,
  render_max_output_bytes: 1_000_000,
  render_max_heap_words: 2_000_000,
  subject_max_bytes: 998
