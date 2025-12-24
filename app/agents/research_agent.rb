class ResearchAgent < ApplicationAgent
  # Enable context persistence for tracking prompts and generations
  has_context
  has_tools :web_search, :web_fetch

  # Tool descriptions for UI feedback during execution
  tool_description :web_search, ->(args) { "Searching the web for '#{args[:query]}'..." }
  tool_description :web_fetch, ->(args) { "Fetching content from #{args[:url]&.truncate(50)}..." }

  generate_with :openai,
    model: "gpt-4o",
    stream: true

  on_stream :broadcast_chunk
  on_stream_close :broadcast_complete

  # Research a topic and provide context
  def research
    @query = params[:query]
    @topic = params[:topic]
    @card_context = params[:context]
    @depth = params[:depth] || "standard"

    create_context(
      contextable: params[:contextable],
      input_params: { query: @query, topic: @topic, card_context: @card_context, depth: @depth }
    )

    prompt tools: tools, tool_choice: "auto"
  end

  # Generate related topics or questions
  def suggest_topics
    @topic = params[:topic]
    @card_context = params[:context]

    create_context(
      contextable: params[:contextable],
      input_params: { topic: @topic, card_context: @card_context }
    )

    prompt tools: tools, tool_choice: "auto"
  end

  # Break down a task into subtasks
  def break_down_task
    @task = params[:task]
    @card_context = params[:context]

    create_context(
      contextable: params[:contextable],
      input_params: { task: @task, card_context: @card_context }
    )

    prompt tools: tools, tool_choice: "auto"
  end

  # Tool: Search the web for information
  def web_search(query:, num_results: 5)
    num_results = [ num_results.to_i, 10 ].min
    num_results = 5 if num_results < 1

    results = perform_web_search(query, num_results)

    if results.any?
      format_search_results(results)
    else
      no_results_message(query)
    end
  rescue => e
    Rails.logger.error "[ResearchAgent] Web search error: #{e.message}"
    "Search failed: #{e.message}"
  end

  def no_results_message(query)
    if brave_api_key.blank?
      <<~MSG.strip
        No search results found for: #{query}

        Note: Web search is currently using DuckDuckGo which may block automated requests.
        If the user provided a specific URL, try using web_fetch directly on that URL.
        For more reliable search results, configure BRAVE_SEARCH_API_KEY environment variable.
      MSG
    else
      "No search results found for: #{query}"
    end
  end

  # Tool: Fetch content from a URL
  def web_fetch(url:, extract_main_content: true)
    content = fetch_url_content(url)

    if extract_main_content
      extract_main_text(content)
    else
      content
    end
  rescue => e
    Rails.logger.error "[ResearchAgent] Web fetch error: #{e.message}"
    "Failed to fetch URL: #{e.message}"
  end

  private

  def perform_web_search(query, num_results)
    # Try Brave Search API first if configured
    if brave_api_key.present?
      perform_brave_search(query, num_results)
    else
      perform_duckduckgo_search(query, num_results)
    end
  end

  def brave_api_key
    ENV["BRAVE_SEARCH_API_KEY"] || Rails.application.credentials.dig(:brave, :search_api_key)
  end

  def perform_brave_search(query, num_results)
    uri = URI("https://api.search.brave.com/res/v1/web/search")
    uri.query = URI.encode_www_form(q: query, count: num_results)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["X-Subscription-Token"] = brave_api_key

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      parse_brave_results(data, num_results)
    else
      Rails.logger.warn "[ResearchAgent] Brave search failed: #{response.code}, falling back to DuckDuckGo"
      perform_duckduckgo_search(query, num_results)
    end
  rescue => e
    Rails.logger.warn "[ResearchAgent] Brave search error: #{e.message}, falling back to DuckDuckGo"
    perform_duckduckgo_search(query, num_results)
  end

  def parse_brave_results(data, num_results)
    results = []
    web_results = data.dig("web", "results") || []

    web_results.first(num_results).each do |result|
      results << {
        title: result["title"],
        url: result["url"],
        snippet: result["description"] || ""
      }
    end

    results
  end

  def perform_duckduckgo_search(query, num_results)
    encoded_query = CGI.escape(query)
    search_url = "https://html.duckduckgo.com/html/?q=#{encoded_query}"

    html = fetch_search_page(search_url)
    results = parse_duckduckgo_results(html, num_results)

    # Check if we got blocked by CAPTCHA
    if results.empty? && html.include?("anomaly-modal")
      Rails.logger.warn "[ResearchAgent] DuckDuckGo blocked with CAPTCHA. Consider configuring BRAVE_SEARCH_API_KEY."
      []
    else
      results
    end
  end

  def fetch_search_page(url)
    uri = URI.parse(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri.request_uri)
    # Use a realistic browser User-Agent
    request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
    request["Accept-Language"] = "en-US,en;q=0.9"
    request["Accept-Encoding"] = "gzip, deflate, br"
    request["Cache-Control"] = "no-cache"
    request["Sec-Ch-Ua"] = '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"'
    request["Sec-Ch-Ua-Mobile"] = "?0"
    request["Sec-Ch-Ua-Platform"] = '"macOS"'
    request["Sec-Fetch-Dest"] = "document"
    request["Sec-Fetch-Mode"] = "navigate"
    request["Sec-Fetch-Site"] = "none"
    request["Sec-Fetch-User"] = "?1"
    request["Upgrade-Insecure-Requests"] = "1"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      body = response.body
      # Handle gzip encoding
      if response["Content-Encoding"] == "gzip"
        body = Zlib::GzipReader.new(StringIO.new(body)).read
      end
      body.force_encoding("UTF-8")
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  def parse_duckduckgo_results(html, num_results)
    doc = Nokogiri::HTML(html)
    results = []

    doc.css(".result").first(num_results).each do |result|
      title_elem = result.at_css(".result__title a, .result__a")
      snippet_elem = result.at_css(".result__snippet")
      url_elem = result.at_css(".result__url")

      next unless title_elem

      # DuckDuckGo uses redirect URLs, extract the actual URL
      href = title_elem["href"] || ""
      actual_url = if href.include?("uddg=")
        CGI.parse(URI.parse(href).query || "")["uddg"]&.first
      else
        url_elem&.text&.strip
      end

      results << {
        title: title_elem.text.strip,
        url: actual_url,
        snippet: snippet_elem&.text&.strip || ""
      }
    end

    results
  end

  def format_search_results(results)
    formatted = results.map.with_index do |result, i|
      <<~RESULT
        #{i + 1}. **#{result[:title]}**
           URL: #{result[:url]}
           #{result[:snippet]}
      RESULT
    end

    "Search Results:\n\n#{formatted.join("\n")}"
  end

  def fetch_url_content(url)
    uri = URI.parse(url)
    raise ArgumentError, "Invalid URL scheme" unless %w[http https].include?(uri.scheme)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "Mozilla/5.0 (compatible; FizzyResearchBot/1.0)"
    request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    response = http.request(request)

    case response
    when Net::HTTPRedirection
      fetch_url_content(response["location"])
    when Net::HTTPSuccess
      response.body.force_encoding("UTF-8")
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  def extract_main_text(html)
    doc = Nokogiri::HTML(html)

    # Remove scripts, styles, nav, footer, etc.
    doc.css("script, style, nav, footer, header, aside, .nav, .footer, .header, .sidebar, .menu, .advertisement, .ad").remove

    # Try to find main content
    main_content = doc.at_css("main, article, .content, .post, .entry, #content, #main") || doc.at_css("body")

    return "No content found" unless main_content

    # Extract text and clean up whitespace
    text = main_content.text
      .gsub(/\s+/, " ")
      .strip

    # Truncate if too long (keep under ~8000 chars for context window)
    if text.length > 8000
      text = text[0, 8000] + "\n\n[Content truncated...]"
    end

    text
  end

  def broadcast_chunk(chunk)
    return unless chunk.message
    return unless params[:stream_id]

    Rails.logger.info "[ResearchAgent] Broadcasting chunk to stream_id: #{params[:stream_id]}, content length: #{chunk.message[:content].length}"
    ActionCable.server.broadcast(params[:stream_id], { content: chunk.message[:content] })
  end

  def broadcast_complete(chunk)
    return unless params[:stream_id]

    Rails.logger.info "[ResearchAgent] Broadcasting completion to stream_id: #{params[:stream_id]}"
    ActionCable.server.broadcast(params[:stream_id], { done: true })
  end
end
