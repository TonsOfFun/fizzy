# frozen_string_literal: true

require "test_helper"

class ResearchAgentTest < ActiveSupport::TestCase
  setup do
    @agent = ResearchAgent.new
    @agent.params = {}
  end

  # === Prompt Configuration Tests ===

  test "instructions template is loaded into prompt_options" do
    # Process the research action to set up prompt options
    @agent.process(:research)

    # Get the prepared parameters that would be sent to the provider
    parameters = @agent.send(:prepare_prompt_parameters)

    assert parameters[:instructions].present?, "Instructions should be set from template"
    assert parameters[:instructions].include?("research assistant"), "Instructions should contain expected content"
    assert parameters[:instructions].include?("web_search"), "Instructions should mention web_search tool"
    assert parameters[:instructions].include?("web_fetch"), "Instructions should mention web_fetch tool"
  end

  test "tools are passed to prompt_options" do
    @agent.process(:research)

    assert @agent.prompt_options[:tools].present?, "Tools should be set in prompt_options"
    assert_equal 2, @agent.prompt_options[:tools].length

    tool_names = @agent.prompt_options[:tools].map { |t| t[:name] }
    assert_includes tool_names, "web_search"
    assert_includes tool_names, "web_fetch"
  end

  test "prepared parameters include both instructions and tools" do
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)

    assert parameters[:instructions].present?, "Instructions should be present"
    assert parameters[:tools].present?, "Tools should be present"
  end

  test "tools are in correct OpenAI format" do
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)
    tools = parameters[:tools]

    tools.each do |tool|
      assert_equal "function", tool[:type], "Tool type should be 'function'"
      assert tool[:name].present?, "Tool should have a name"
      assert tool[:description].present?, "Tool should have a description"
      assert tool[:parameters].present?, "Tool should have parameters"
      assert_equal "object", tool[:parameters][:type], "Tool parameters type should be 'object'"
    end
  end

  test "tools_function callback is set for tool execution" do
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)

    assert parameters[:tools_function].present?, "tools_function callback should be set"
    assert parameters[:tools_function].is_a?(Proc), "tools_function should be a Proc"
  end

  test "tools_function can invoke web_search tool" do
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)
    tools_function = parameters[:tools_function]

    # The tools_function should be able to call web_search
    VCR.use_cassette("duckduckgo_search_via_callback") do
      result = tools_function.call("web_search", query: "Ruby programming")

      assert result.present?
      assert result.is_a?(String)
    end
  end

  test "tools_function can invoke web_fetch tool" do
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)
    tools_function = parameters[:tools_function]

    # The tools_function should be able to call web_fetch
    VCR.use_cassette("web_fetch_via_callback") do
      result = tools_function.call("web_fetch", url: "https://example.com")

      assert result.present?
      assert result.is_a?(String)
    end
  end

  test "research action template is loaded as message" do
    @agent.params = { query: "test query", topic: "test topic" }
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)

    # Check that messages are set from the research.text.erb template
    assert parameters[:messages].present?, "Messages should be set from template"

    message_content = parameters[:messages].first
    message_text = message_content.is_a?(Hash) ? message_content[:content] : message_content.to_s

    assert message_text.include?("test query") || message_text.include?("test topic"),
      "Message should include the query or topic from params"
  end

  test "research message template instructs use of tools" do
    @agent.params = { query: "What is SF Ruby?", topic: "SF Ruby meetup" }
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)
    messages = parameters[:messages]

    # Get the message content
    message_text = messages.map do |m|
      m.is_a?(Hash) ? m[:content].to_s : m.to_s
    end.join(" ")

    # The research template should instruct to use web_search and web_fetch
    assert message_text.include?("web_search") || message_text.include?("web_fetch"),
      "Research template should mention using the tools. Got: #{message_text[0..500]}"
  end

  test "complete prompt structure for debugging" do
    @agent.params = { query: "What is SF Ruby?", topic: "SF Ruby" }
    @agent.process(:research)

    parameters = @agent.send(:prepare_prompt_parameters)

    # Debug output - uncomment to see full structure
    # puts "\n=== COMPLETE PROMPT PARAMETERS ==="
    # puts "Instructions: #{parameters[:instructions]&.truncate(200)}"
    # puts "Tools count: #{parameters[:tools]&.length}"
    # puts "Tool names: #{parameters[:tools]&.map { |t| t[:name] }}"
    # puts "Messages count: #{parameters[:messages]&.length}"
    # puts "First message: #{parameters[:messages]&.first.to_s.truncate(200)}"
    # puts "Model: #{parameters[:model]}"
    # puts "Stream: #{parameters[:stream]}"
    # puts "================================\n"

    # Verify complete structure
    assert parameters[:instructions].present?, "Should have instructions"
    assert parameters[:tools].present?, "Should have tools"
    assert parameters[:messages].present?, "Should have messages"
    assert parameters[:tools_function].present?, "Should have tools_function callback"
    assert_equal 2, parameters[:tools].length, "Should have 2 tools"
  end

  # === Tool Configuration Tests ===

  test "has web_search and web_fetch tools configured" do
    assert_equal [ :web_search, :web_fetch ], ResearchAgent._tool_names
  end

  test "tools method returns tool schemas" do
    tools = @agent.tools

    assert_equal 2, tools.length

    tool_names = tools.map { |t| t[:name] }
    assert_includes tool_names, "web_search"
    assert_includes tool_names, "web_fetch"
  end

  test "web_search tool schema has correct parameters" do
    tools = @agent.tools
    web_search = tools.find { |t| t[:name] == "web_search" }

    assert_equal "function", web_search[:type]
    assert web_search[:description].present?
    assert_equal "object", web_search[:parameters][:type]
    assert web_search[:parameters][:properties].key?(:query) || web_search[:parameters][:properties].key?("query")
  end

  test "web_fetch tool schema has correct parameters" do
    tools = @agent.tools
    web_fetch = tools.find { |t| t[:name] == "web_fetch" }

    assert_equal "function", web_fetch[:type]
    assert web_fetch[:description].present?
    assert_equal "object", web_fetch[:parameters][:type]
    assert web_fetch[:parameters][:properties].key?(:url) || web_fetch[:parameters][:properties].key?("url")
  end

  test "web_search method performs search and returns results" do
    VCR.use_cassette("duckduckgo_search") do
      result = @agent.web_search(query: "Ruby on Rails")

      assert result.present?
      assert result.include?("Search Results") || result.include?("No search results")
    end
  end

  test "web_fetch method fetches URL content" do
    VCR.use_cassette("web_fetch_example") do
      result = @agent.web_fetch(url: "https://example.com")

      assert result.present?
      assert result.is_a?(String)
    end
  end

  test "web_fetch extracts main content by default" do
    VCR.use_cassette("web_fetch_example") do
      result = @agent.web_fetch(url: "https://example.com", extract_main_content: true)

      # Should not contain script tags or nav elements after extraction
      refute result.include?("<script")
      refute result.include?("<nav")
    end
  end

  test "web_search handles errors gracefully" do
    # Mock fetch_url_content to raise an error
    @agent.define_singleton_method(:fetch_url_content) do |_url|
      raise "Network error"
    end

    result = @agent.web_search(query: "test")

    assert result.include?("Search failed")
  end

  test "web_fetch handles errors gracefully" do
    result = @agent.web_fetch(url: "not-a-valid-url")

    assert result.include?("Failed to fetch URL")
  end

  test "web_fetch rejects non-http schemes" do
    result = @agent.web_fetch(url: "file:///etc/passwd")

    assert result.include?("Failed to fetch URL")
  end
end
