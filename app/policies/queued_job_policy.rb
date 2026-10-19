class QueuedJobPolicy
  def initialize(brand, job)
    @brand = brand
    @job = job
  end

  def retry?
    Scope.new(@brand, GoodJob::Job).resolve.exists?(id: @job.id)
  end

  class Scope
    def initialize(brand, scope)
      @brand = brand
      @scope = scope
    end

    def resolve
      return @scope.none unless @brand

      # Match only known job argument shapes to records owned by this brand.
      # Global reconciliation and jobs whose source was deleted are not attributable.
      @scope.where(<<~SQL, brand_id: @brand.id)
        (good_jobs.job_class = 'Alerts::ReconcileJob' AND EXISTS (
          SELECT 1 FROM products WHERE products.brand_id = :brand_id
          AND products.id::text = good_jobs.serialized_params #>> '{arguments,0,product_id}'
        )) OR
        (good_jobs.job_class = 'Alerts::SimulateSmsJob' AND EXISTS (
          SELECT 1 FROM alerts WHERE alerts.brand_id = :brand_id
          AND alerts.id::text = good_jobs.serialized_params #>> '{arguments,0}'
        )) OR
        (good_jobs.job_class IN ('Notifications::DispatchJob', 'Notifications::DeliverJob') AND (
          (good_jobs.serialized_params #>> '{arguments,0}' = 'alert_no_inventory' AND EXISTS (
            SELECT 1 FROM alerts WHERE alerts.brand_id = :brand_id
            AND alerts.id::text = good_jobs.serialized_params #>> '{arguments,1}'
          )) OR
          (good_jobs.serialized_params #>> '{arguments,0}' = 'alert_price_change' AND EXISTS (
            SELECT 1 FROM tracking_events JOIN products ON products.id = tracking_events.product_id
            WHERE products.brand_id = :brand_id
            AND tracking_events.id::text = good_jobs.serialized_params #>> '{arguments,1}'
          ))
        ))
      SQL
    end
  end
end
