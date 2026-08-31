defmodule Letterpress.Renderer.FiltersTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Letterpress.Renderer.Filters

  doctest Letterpress.Renderer.Filters

  test "escapes HTML text and attributes by context" do
    assert {:ok, "&lt;a&gt;&amp;"} = Filters.escape("<a>&", "html_text")
    assert {:ok, "&quot;&#39;&amp;"} = Filters.escape("\"'&", "html_attribute")
    assert {:ok, "42"} = Filters.escape(42, "text")
    assert {:ok, ~s({"safe":true})} = Filters.escape(%{"safe" => true}, "none")
  end

  test "validates subjects, URLs, and internal filter calls" do
    assert {:ok, "Notice"} = Filters.escape("Notice", "subject")
    assert :error = Filters.escape("header\r\ninjection", "subject")
    assert :error = Filters.escape(String.duplicate("x", 999), "subject")

    for safe <- ["https://example.test?a=1&b=2", "/account", "#section", "relative/path"] do
      assert {:ok, _} = Filters.escape(safe, "url")
    end

    for unsafe <- ["javascript:alert(1)", "//evil.example", "https://safe.test\r\nX: bad"] do
      assert :error = Filters.escape(unsafe, "url")
    end

    assert {:ok, "Ada"} = Filters.apply("letterpress_escape", ["Ada", "text"])
    assert :error = Filters.apply("escape", ["Ada", "text"])
    assert :error = Filters.escape("Ada", "css")
  end
end
