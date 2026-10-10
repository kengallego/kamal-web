Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :profile, only: %i[ edit update ]

  resources :projects do
    member do
      post :sync
    end

    scope module: :projects do
      resources :command_runs, only: %i[ index show create ] do
        post :cancel, on: :member
      end
      resource :commands, only: :show
      resources :console_sessions, only: %i[ index create show ], path: "console"
      resource :monitoring, only: %i[ show create ], controller: :monitoring
      resource :proxy, only: :show
      resource :config, only: :show
      resources :environment_variables, except: %i[ index show ]
      resources :project_files, except: %i[ index show ]
      resource :webhook_token, only: :create
      resource :settings, only: :show
    end
  end

  resources :users, except: :show
  resource :settings, only: %i[ edit update ] do
    post :regenerate_status_board_token
    post :reset_ignored_services
  end
  resource :discovery, only: :create

  get "status/:token" => "status_boards#show", as: :status_board
  post "hooks/deploy/:token" => "deploy_hooks#create", as: :deploy_hook

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
