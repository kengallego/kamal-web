Rails.application.routes.draw do
  resource :session
  resource :preferences, only: :update

  resources :projects do
    member do
      post :sync
    end

    scope module: :projects do
      resources :command_runs, only: %i[ index show create ] do
        post :cancel, on: :member
      end
      resource :commands, only: :show
      resource :logs, only: %i[ show create ]
      resources :console_sessions, only: %i[ index create show ], path: "console"
      resource :monitoring, only: %i[ show create ], controller: :monitoring
      resource :proxy, only: :show
      resource :config, only: :show
      resource :releases, only: :show
      resource :deploy_preview, only: :show
      resource :containers, only: :show
      resources :environment_variables, except: %i[ index show ]
      resources :project_files, except: %i[ index show ]
      resource :webhook_token, only: :create
      resource :settings, only: :show
    end
  end

  resources :servers do
    post :check, on: :member
  end

  resource :settings, only: %i[ edit update ] do
    post :regenerate_status_board_token
    post :reset_ignored_services
    post :update_instance
  end
  resource :discovery, only: :create
  resource :backup, only: %i[ show create ] do
    get "stored/:name", action: :stored, as: :stored, format: false, constraints: { name: /[^\/]+/ }
  end

  get "status/:token" => "status_boards#show", as: :status_board
  post "hooks/deploy/:token" => "deploy_hooks#create", as: :deploy_hook

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
