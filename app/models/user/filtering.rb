class User::Filtering
  include Rails.application.routes.url_helpers

  attr_reader :user, :filter, :expanded

  delegate :as_params, :any?, to: :filter
  delegate :only_closed?, to: :filter

  def initialize(user, filter, expanded: false)
    @user, @filter, @expanded = user, filter, expanded
  end

  def collections
    @collections ||= user.collections.ordered_by_recently_accessed
  end

  def selected_collection_titles
    if filter.collections.none?
      [ collections.one? ? collections.first.name : "All collections" ]
    else
      filter.collections.map(&:name)
    end
  end

  def selected_collections_label
    selected_collection_titles.to_sentence
  end

  def tags
    @tags ||= Tag.all.alphabetically
  end

  def users
    @users ||= User.active.alphabetically
  end

  def filters
    @filters ||= Current.user.filters.all
  end

  def expanded?
    @expanded
  end

  def any?
    filter.used?(ignore_collections: true)
  end

  def show_indexed_by?
    expanded? || !filter.indexed_by.all?
  end

  def show_sorted_by?
    expanded? || !filter.sorted_by.latest?
  end

  def show_tags?
    return unless Tag.any?
    expanded? || filter.tags.any?
  end

  def show_assignees?
    expanded? || filter.assignees.any?
  end

  def show_creators?
    expanded? || filter.creators.any?
  end

  def show_closers?
    expanded? || filter.closers.any?
  end

  def enable_collection_filtering(&block)
    @collection_filtering_route_resolver = block
  end

  def self_filter_path(...)
    if supports_collection_filtering?
      @collection_filtering_route_resolver.call(...)
    else
      cards_path(...)
    end
  end

  def cache_key
    ActiveSupport::Cache.expand_cache_key( [ user, filter, expanded? ], "user-filtering")
  end

  private
    def supports_collection_filtering?
      @collection_filtering_route_resolver.present?
    end
end
