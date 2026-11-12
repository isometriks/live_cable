# frozen_string_literal: true

Dummy::Application.routes.draw do
  mount ActionCable.server => '/cable'

  root 'home#index'
  get '/counter', to: 'home#counter'
  get '/children', to: 'home#children'
  get '/table_rows', to: 'home#table_rows'
  get '/shelf', to: 'home#shelf'
  get '/recursive', to: 'home#recursive'
  get '/form_test', to: 'home#form_test'
  get '/error_test', to: 'home#error_test'
  get '/error_on_subscribe_test', to: 'home#error_on_subscribe_test'
  get '/local_vars', to: 'home#local_vars'
  get '/checklist', to: 'home#checklist'
  get '/compound', to: 'home#compound'
  get '/plain_erb', to: 'home#plain_erb'
  get '/plain_guard', to: 'home#plain_guard'
  get '/render_component', to: 'home#render_component'
  get '/loading', to: 'home#loading'
  get '/event_test', to: 'home#event_test'
  get '/tenant', to: 'home#tenant'
  get '/whoami', to: 'home#whoami'
  get '/shell', to: 'home#shell'
  get '/lanes', to: 'home#lanes'
  get '/toggle', to: 'home#toggle'
  get '/panel', to: 'home#panel'
  get '/shell_frame', to: 'home#shell_frame'
  get '/shell_stream', to: 'home#shell_stream'
  post '/shell_stream', to: 'home#replace_shell'
  get '/sign_in', to: 'home#sign_in'
  get '/chat_test', to: 'home#chat_test'
  get '/reactive_inputs', to: 'home#reactive_inputs'
  get '/chores', to: 'home#chores'
  get '/page_context', to: 'home#page_context'
  post '/page_context', to: 'home#page_context_submitted'
  get '/framed_page_context', to: 'home#framed_page_context'
  # Like Devise's authenticate and authenticated, on a socket with no one
  # signed in and on one with no Warden at all
  constraints(->(_request) { throw :warden }) { get '/authenticate', to: 'home#page_context' }
  constraints(->(request) { request.env['warden'].authenticated? }) { get '/authenticated', to: 'home#page_context' }
  get '/rotate_session_token', to: 'home#rotate_session_token'
  get '/disconnect_sockets', to: 'home#disconnect_sockets'
  get '/revoke_session', to: 'home#revoke_session'
end
