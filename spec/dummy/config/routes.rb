# frozen_string_literal: true

Dummy::Application.routes.draw do
  mount ActionCable.server => '/cable'

  root 'home#index'
  get '/counter', to: 'home#counter'
  get '/children', to: 'home#children'
  get '/recursive', to: 'home#recursive'
  get '/form_test', to: 'home#form_test'
  get '/error_test', to: 'home#error_test'
  get '/error_on_subscribe_test', to: 'home#error_on_subscribe_test'
  get '/local_vars', to: 'home#local_vars'
  get '/compound', to: 'home#compound'
  get '/plain_erb', to: 'home#plain_erb'
end
