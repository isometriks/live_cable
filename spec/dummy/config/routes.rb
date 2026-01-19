# frozen_string_literal: true

Dummy::Application.routes.draw do
  mount ActionCable.server => '/cable'

  root 'home#index'
  get '/counter', to: 'home#counter'
  get '/children', to: 'home#children'
end
