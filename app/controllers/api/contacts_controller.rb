module Api
  class ContactsController < BaseController
    PAGE_SIZE = 20
    after_action :verify_policy_scoped

    rescue_from ActionController::ParameterMissing, ArgumentError do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def index
      scope = policy_scope(Contact)
      page_value = params.fetch(:page, "1").to_s
      unless page_value.match?(/\A[1-9][0-9]{0,5}\z/)
        return render json: { error: "Page must be a positive integer (1–999999)." }, status: :unprocessable_entity
      end

      keyword = params.fetch(:q, "")
      unless keyword.is_a?(String) && keyword.length <= 200
        return render json: { error: "Search must be text of at most 200 characters." }, status: :unprocessable_entity
      end

      if keyword.strip.present?
        pattern = "%#{Contact.sanitize_sql_like(keyword.strip)}%"
        scope = scope.where("name ILIKE :pattern OR email ILIKE :pattern OR phone ILIKE :pattern", pattern: pattern)
      end

      page = page_value.to_i
      total = scope.count
      contacts = scope.order(id: :desc).offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
      render json: { contacts: contacts.map { |contact| serialize(contact) },
                     pagination: { page: page, per_page: PAGE_SIZE, total: total, pages: (total.to_f / PAGE_SIZE).ceil } }
    end

    def show
      contact = policy_scope(Contact).find(params[:id])
      render json: { contact: serialize(contact) }
    end

    def create
      contact = policy_scope(Contact).new(contact_params)
      save_contact(contact, :created)
    end

    def update
      contact = policy_scope(Contact).find(params[:id])
      contact.assign_attributes(contact_params)
      save_contact(contact, :ok)
    end

    private

    def contact_params
      input = params.require(:contact)
      raise ArgumentError, "Contact must be an object." unless input.is_a?(ActionController::Parameters)

      %w[name email phone].each do |field|
        next unless input.key?(field)
        unless input[field].is_a?(String) || (field != "name" && input[field].nil?)
          raise ArgumentError, "#{field.capitalize} must be text."
        end
      end
      if input.key?(:setup)
        setup = input[:setup]
        unless setup.is_a?(ActionController::Parameters) && setup.keys.sort == Contact::ALERT_TYPES.sort &&
               setup.values.all? { |value| value == true || value == false }
          raise ArgumentError, "Choose true or false for both alert preferences."
        end
      end
      input.permit(:name, :email, :phone, setup: Contact::ALERT_TYPES)
    end

    def save_contact(contact, status)
      if contact.save
        render json: { contact: serialize(contact) }, status: status
      else
        render json: { error: contact.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def serialize(contact)
      contact.slice(:id, :name, :email, :phone, :setup)
    end
  end
end
