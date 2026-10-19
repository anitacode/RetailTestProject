module Api
  class BaseController < ApplicationController
    include Pundit::Authorization
    before_action :disable_caching
    before_action :require_brand

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "Record not found." }, status: :not_found
    end
    rescue_from ActionController::InvalidAuthenticityToken do
      render json: { error: "Your session expired. Refresh and try again." }, status: :unprocessable_entity
    end

    private

    def pundit_user
      current_brand
    end

    def current_brand
      @current_brand ||= Brand.find_by(id: session[:brand_id])
    end

    def require_brand
      render json: { error: "Sign in with your brand name to continue." }, status: :unauthorized unless current_brand
    end

    def disable_caching
      response.headers["Cache-Control"] = "no-store"
    end
  end
end
