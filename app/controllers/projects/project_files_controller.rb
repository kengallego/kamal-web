class Projects::ProjectFilesController < Projects::BaseController
  before_action :set_file, only: %i[ edit update destroy ]

  def new
    @file = @project.project_files.new(path: params[:path])
  end

  def create
    @file = @project.project_files.new(file_params)

    if @file.save
      redirect_to project_settings_path(@project), notice: "#{@file.path} saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = file_params
    attributes.delete(:content) if attributes[:content].blank?

    if @file.update(attributes)
      redirect_to project_settings_path(@project), notice: "#{@file.path} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @file.destroy!
    redirect_to project_settings_path(@project), notice: "#{@file.path} deleted.", status: :see_other
  end

  private
    def set_file
      @file = @project.project_files.find(params[:id])
    end

    def file_params
      params.expect(project_file: [ :path, :content ])
    end
end
