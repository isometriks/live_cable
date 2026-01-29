# frozen_string_literal: true

module Live
  class FormTest < LiveCable::Component
    reactive :user_name, -> { 'John Doe' }
    reactive :user_email, -> { 'john@example.com' }
    reactive :address_street, -> { '123 Main St' }
    reactive :address_city, -> { 'Anytown' }

    actions :update_form

    def update_form(params)
      self.user_name = params[:user][:name] if params[:user]&.key?(:name)
      self.user_email = params[:user][:email] if params[:user]&.key?(:email)

      if params[:user]&.key?(:address_attributes)
        self.address_street = params[:user][:address_attributes][:street]
        self.address_city = params[:user][:address_attributes][:city]
      end
    end
  end
end
