module Api
  class AlertsController < BaseController
    PAGE_SIZE = 20

    after_action :verify_policy_scoped

    def index
      scope = policy_scope(Alert)
      page = params.fetch(:page, "1").to_i

      unless page&.positive?
        return render(
          json: { error: "Page must be a positive integer." },
          status: :unprocessable_entity
        )
      end

      total = scope.count
      alerts = scope
               .newest_first
               .includes(:product, :store, :previous_event, :triggering_event)
               .offset((page.to_i - 1) * PAGE_SIZE)
               .limit(PAGE_SIZE)

      render json: { alerts: alerts.map { |alert| serialize(alert) }, unseen_count: scope.unseen.count,
                     pagination: { page: page.to_i, per_page: PAGE_SIZE, total: total, pages: (total.to_f / PAGE_SIZE).ceil } }
    end

    def show
      alert = policy_scope(Alert)
              .includes(:product, :store, :previous_event, :triggering_event)
              .find(params[:id])

      render json: { alert: serialize(alert) }
    end

    def seen
      alert = policy_scope(Alert).find(params[:id])
      alert.mark_seen!
      render json: { seen_at: alert.seen_at.iso8601(6) }
    end

    private

    def serialize(alert)
      { id: alert.id, alert_type: alert.alert_type, seen_at: alert.seen_at&.iso8601(6), observed_at: alert.observed_at.iso8601,
        product: { id: alert.product_id, name: alert.product.name },
        store: { id: alert.store_id, address: alert.store.address },
        observations: [alert.previous_event, alert.triggering_event].map do |event|
          { id: event.id, event_time: event.event_time.iso8601 }.merge(
            alert.alert_type == "alert_price_change" ? event.value.slice("amount", "currency") : event.value.slice("quantity")
          )
        end }
    end
  end
end
