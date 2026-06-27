class AirspaceChannel < ApplicationCable::Channel
  def subscribed
    stream_from "airspace"
  end
end
