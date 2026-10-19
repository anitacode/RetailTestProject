module Api
  class QueuedJobsController < BaseController
    after_action :verify_policy_scoped
    after_action :verify_authorized, only: :retry_job

    def index
      scope = policy_scope(GoodJob::Job, policy_scope_class: QueuedJobPolicy::Scope)
      page_value = params.fetch(:page, "1").to_s
      unless page_value.match?(/\A[1-9][0-9]{0,5}\z/)
        return render json: { error: "Page must be a positive integer (1–999999)." }, status: :unprocessable_entity
      end

      page = page_value.to_i
      total = scope.count
      jobs = scope.order(created_at: :desc, id: :desc).offset((page - 1) * 20).limit(20).includes_advisory_locks
      render json: { jobs: jobs.map { |job| serialize(job) },
                     pagination: { page: page, per_page: 20, total: total, pages: (total.to_f / 20).ceil } }
    end

    def retry_job
      job = policy_scope(GoodJob::Job, policy_scope_class: QueuedJobPolicy::Scope).find(params[:id])
      authorize job, :retry?, policy_class: QueuedJobPolicy
      unless job.discarded? && !job.running?
        return render json: { error: "Only failed jobs can be retried. Refresh the queue status." }, status: :conflict
      end

      job.retry_job
      render json: { status: "accepted" }, status: :accepted
    rescue Pundit::NotAuthorizedError
      render json: { error: "Record not found." }, status: :not_found
    rescue GoodJob::Job::ActionForStateMismatchError, GoodJob::AdvisoryLockable::RecordAlreadyAdvisoryLockedError
      render json: { error: "This job is already queued or running. Refresh the queue status." }, status: :conflict
    rescue GoodJob::Job::ActiveJobDeserializationError
      render json: { error: "This job can no longer be retried because its data is unavailable." }, status: :conflict
    rescue GoodJob::Job::AdapterNotGoodJobError
      render json: { error: "The job worker adapter is unavailable." }, status: :service_unavailable
    end

    private

    def serialize(job)
      { id: job.id, job_class: job.job_class, queue: job.queue_name, status: job_status(job),
        attempts: job.executions_count, created_at: job.created_at.iso8601,
        scheduled_at: job.scheduled_at&.iso8601, finished_at: job.finished_at&.iso8601 }
    end

    def job_status(job)
      return "failed" if job.discarded?
      return "completed" if job.succeeded?
      return "running" if job.running?
      return "retrying" if job.error.present?
      return "scheduled" if job.scheduled_at && job.scheduled_at > Time.current

      "queued"
    end
  end
end
