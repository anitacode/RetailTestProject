module Api
  class TrackingEventsController < BaseController
    PAGE_SIZE = 20
    OBSERVED_ORDERS = {
      "desc" => "tracking_events.event_time DESC NULLS LAST, tracking_events.id DESC",
      "asc" => "tracking_events.event_time ASC NULLS LAST, tracking_events.id ASC"
    }.freeze
    after_action :verify_policy_scoped

    def index
      scope = policy_scope(TrackingEvent)
      page_value = params.fetch(:page, "1").to_s
      unless page_value.match?(/\A[1-9][0-9]{0,5}\z/)
        return render json: { error: "Page must be a positive integer (1–999999)." }, status: :unprocessable_entity
      end

      ordering = OBSERVED_ORDERS[params.fetch(:order, "desc")]
      unless ordering
        return render json: { error: "Order must be asc or desc." }, status: :unprocessable_entity
      end

      page = page_value.to_i
      total = scope.count(:all)
      events = scope.reselect("tracking_events.*").order(Arel.sql(ordering))
                    .includes(:product, :store).offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
      render json: { tracking_events: events.map { |event| serialize(event) },
                     pagination: { page: page, per_page: PAGE_SIZE, total: total, pages: (total.to_f / PAGE_SIZE).ceil } }
    end

    private

    def serialize(event)
      fields = event.price_tracker? ? %w[amount currency] : %w[quantity]
      { id: event.id, event_type: event.event_type, event_time: event.event_time&.iso8601(6),
        value: event.value.slice(*fields),
        product: { id: event.product_id, name: event.product.name },
        store: { id: event.store_id, address: event.store.address } }
    end
  end
end
