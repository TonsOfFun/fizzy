require "ostruct"

class CardsController < ApplicationController
  include CollectionScoped, Collections::ColumnsScoped

  skip_before_action :set_collection, only: :index
  before_action :set_card, only: %i[ show edit update destroy ]

  enable_collection_filtering only: :index

  PAGE_SIZE = 50

  def index
    @considering = page_and_filter_for @filter.with(engagement_status: "considering"), per_page: PAGE_SIZE
    @on_deck = page_and_filter_for @filter.with(engagement_status: "on_deck"), per_page: PAGE_SIZE
    @doing = page_and_filter_for @filter.with(engagement_status: "doing"), per_page: PAGE_SIZE
    @closed = page_and_filter_for_closed_cards

    fresh_when etag: [ @considering, @on_deck, @doing, @closed ].collect { it.page.records }
  end

  def create
    card = @collection.cards.create!
    redirect_to card
  end

  def show
  end

  def edit
  end

  def update
    @card.update! card_params

    if @card.published?
      render_card_replacement
    else
      redirect_to @card
    end
  end

  def destroy
    @card.destroy!
    redirect_to cards_path(collection_ids: [ @card.collection ]), notice: ("Card deleted" unless @card.creating?)
  end

  private
    def set_card
      @card = @collection.cards.find params[:id]
    end

    def card_params
      params.expect(card: [ :status, :title, :description, :image, tag_ids: [] ])
    end

    def render_card_replacement
      render turbo_stream: turbo_stream.replace([ @card, :card_container ], partial: "cards/container", locals: { card: @card.reload })
    end
end
