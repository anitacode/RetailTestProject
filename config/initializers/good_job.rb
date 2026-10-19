Rails.application.configure do
  config.active_job.queue_adapter = Rails.env.test? ? :test : :good_job
  config.good_job.execution_mode = :external
  config.good_job.threads = 1
  config.good_job.poll_interval = 5
  config.good_job.retry_on_unhandled_error = false
end
