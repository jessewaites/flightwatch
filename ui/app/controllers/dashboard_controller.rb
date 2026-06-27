class DashboardController < ApplicationController
  protect_from_forgery with: :exception

  ANOMALIES_PER_PAGE = 10

  def index
    @snapshot = Flightwatch::Workspace.snapshot
    @anomaly_pagy, @anomalies = pagy_array(@snapshot[:anomalies], items: ANOMALIES_PER_PAGE)
  end

  # Load-older: returns a Turbo Stream that appends the next page of anomalies to the feed
  # and swaps in the next "Load older" control. Live new anomalies still prepend via the bus.
  def anomalies
    all = Flightwatch::Workspace.snapshot[:anomalies]
    @anomaly_pagy, @anomalies = pagy_array(all, items: ANOMALIES_PER_PAGE)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end

  def mode
    source = Flightwatch::Workspace.write_mode(params[:source])
    Flightwatch::FileBusBroadcaster.broadcast(Flightwatch::Workspace.path.join("control", "mode.json"))

    render json: { source: source }
  end
end
