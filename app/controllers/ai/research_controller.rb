module AI
  class ResearchController < BaseController
    def research
      stream_id = "research_#{SecureRandom.hex(8)}"

      agent = ResearchAgent.with(
        query: params[:query],
        topic: params[:topic],
        context: params[:context],
        depth: params[:depth] || "standard",
        stream_id: stream_id
      ).research

      if params[:stream]
        render_streaming(agent, stream_id: stream_id)
      else
        render_generation(agent)
      end
    end

    def suggest_topics
      stream_id = "research_#{SecureRandom.hex(8)}"

      agent = ResearchAgent.with(
        topic: params[:topic],
        context: params[:context],
        stream_id: stream_id
      ).suggest_topics

      if params[:stream]
        render_streaming(agent, stream_id: stream_id)
      else
        render_generation(agent)
      end
    end

    def break_down_task
      stream_id = "research_#{SecureRandom.hex(8)}"

      agent = ResearchAgent.with(
        task: params[:task],
        context: params[:context],
        stream_id: stream_id
      ).break_down_task

      if params[:stream]
        render_streaming(agent, stream_id: stream_id)
      else
        render_generation(agent)
      end
    end

    # Unified streaming endpoint for all research actions
    def stream
      action = params[:action_type]
      stream_id = "research_#{SecureRandom.hex(8)}"

      content = params[:selection].presence || params[:full_content]

      # Convert context params to hash if present (avoids unpermitted params errors)
      context = params[:context].present? ? params[:context].to_unsafe_h : nil

      agent = ResearchAgent.with(
        query: content,
        task: content,
        topic: content,
        context: context,
        depth: params[:depth] || "standard",
        stream_id: stream_id
      )

      case action
      when "research"
        agent.research.generate_later
      when "suggest_topics"
        agent.suggest_topics.generate_later
      when "break_down_task"
        agent.break_down_task.generate_later
      else
        return render json: { error: "Unknown action: #{action}" }, status: :unprocessable_entity
      end

      render json: { stream_id: stream_id }
    rescue => e
      Rails.logger.error "[ResearchController] Stream error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
