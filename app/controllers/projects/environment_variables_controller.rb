class Projects::EnvironmentVariablesController < Projects::BaseController
  before_action :require_admin
  before_action :set_variable, only: %i[ edit update destroy ]

  def new
    @variable = @project.environment_variables.new(destination: params[:destination])
  end

  def create
    @variable = @project.environment_variables.new(variable_params)

    if @variable.save
      redirect_to project_settings_path(@project), notice: "#{@variable.key} saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = variable_params
    attributes.delete(:value) if attributes[:value].blank?

    if @variable.update(attributes)
      redirect_to project_settings_path(@project), notice: "#{@variable.key} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @variable.destroy!
    redirect_to project_settings_path(@project), notice: "#{@variable.key} deleted.", status: :see_other
  end

  private
    def set_variable
      @variable = @project.environment_variables.find(params[:id])
    end

    def variable_params
      params.expect(environment_variable: [ :key, :value, :destination ])
    end
end
