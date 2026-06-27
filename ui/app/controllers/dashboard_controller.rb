class DashboardController < ApplicationController
  protect_from_forgery with: :exception

  def index
    @snapshot = Flightwatch::Workspace.snapshot
  end

  def mode
    source = Flightwatch::Workspace.write_mode(params[:source])
    Flightwatch::FileBusBroadcaster.broadcast(Flightwatch::Workspace.path.join("control", "mode.json"))

    render json: { source: source }
  end
end
