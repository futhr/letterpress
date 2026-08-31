defmodule Letterpress.Test.Fixtures do
  @moduledoc false

  def email_source do
    """
    <mjml>
      <mj-head>
        <mj-title>{{ title }}</mj-title>
        <mj-style>.brand { color: {{ brand_color }}; }</mj-style>
      </mj-head>
      <mj-body>
        {% if show_message %}
          <mj-section>
            <mj-column>
              <mj-text css-class="brand">Hello {{ user.name | upcase }}</mj-text>
              <mj-button href="{{ action_url }}">Open account</mj-button>
            </mj-column>
          </mj-section>
        {% endif %}
      </mj-body>
    </mjml>
    """
  end

  def email_schema do
    %{
      "version" => 1,
      "variables" => %{
        "action_url" => definition("url", "delivery", "url"),
        "brand_color" => definition("string", "compile", "css"),
        "show_message" => definition("boolean", "delivery", "none"),
        "title" => definition("string", "delivery", "html_text"),
        "user.name" => definition("string", "delivery", "text")
      }
    }
  end

  def email_compile_options do
    [
      subject: "Notice for {{ user.name }}",
      text: "Hello {{ user.name }}. Open {{ action_url }}",
      compile_values: %{"brand_color" => "#3366ff"}
    ]
  end

  def email_values do
    %{
      "action_url" => "https://example.test/account?a=1&b=2",
      "show_message" => true,
      "title" => "Status",
      "user" => %{"name" => "Ada <Lovelace>"}
    }
  end

  def text_source, do: "Hello {{ name }}, code {{ code }}"

  def text_schema do
    %{
      "version" => 1,
      "variables" => %{
        "code" => definition("string", "delivery", "text"),
        "name" => definition("string", "delivery", "text")
      }
    }
  end

  defp definition(type, phase, context) do
    %{
      "type" => type,
      "phase" => phase,
      "context" => context,
      "required" => true,
      "sensitive" => false
    }
  end
end
