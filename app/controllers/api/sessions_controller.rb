module Api
  class SessionsController < BaseController
    skip_before_action :require_brand

    def show
      render_session
    end

    def create
      name = params[:name]
      unless name.is_a?(String) && name.strip.length.between?(1, 200)
        return render json: { error: "Enter a brand name (1–200 characters)." }, status: :unprocessable_entity
      end

      matches = Brand.where("LOWER(name) = ?", name.strip.downcase).limit(2).to_a
      unless matches.one?
        return render json: { error: "That name does not identify a single brand. Check the name and try again." }, status: :unprocessable_entity
      end

      reset_session
      @current_brand = matches.first
      session[:brand_id] = @current_brand.id
      render_session
    end

    def destroy
      reset_session
      @current_brand = nil
      render_session
    end

    private

    def render_session
      render json: { brand: current_brand&.slice(:id, :name), csrf_token: form_authenticity_token }
    end
  end
end
