module Flightwatch
  class FileBusBroadcaster
    class << self
      def broadcast(path)
        file = Pathname.new(path)
        return unless file.extname == ".json"

        payload = JSON.parse(File.read(file))

        case file.dirname.basename.to_s
        when "flags"
          broadcast_flag(payload)
        when "verdicts"
          broadcast_verdict(payload)
        when "situations"
          broadcast_situation(payload)
        when "control"
          broadcast_control(payload)
        end
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      private

      def broadcast_flag(flag)
        anomaly = Workspace.anomaly_for(flag)
        Turbo::StreamsChannel.broadcast_remove_to("anomalies", target: "anomaly-empty")
        Turbo::StreamsChannel.broadcast_prepend_to(
          "anomalies",
          target: "anomaly-feed",
          partial: "dashboard/anomaly",
          locals: { anomaly: anomaly }
        )
        ActionCable.server.broadcast("airspace", { type: "flag", flag: flag, frame: Workspace.read_frame })
      end

      def broadcast_verdict(verdict)
        anomaly = Workspace.anomaly_for(verdict)
        Turbo::StreamsChannel.broadcast_replace_to(
          "anomalies",
          target: "anomaly_#{anomaly[:id].to_s.parameterize(separator: "_")}",
          partial: "dashboard/anomaly",
          locals: { anomaly: anomaly }
        )
        ActionCable.server.broadcast("airspace", { type: "verdict", verdict: verdict, anomaly: anomaly })
      end

      def broadcast_situation(situation)
        Turbo::StreamsChannel.broadcast_remove_to("synthesis", target: "synthesis-empty")
        Turbo::StreamsChannel.broadcast_prepend_to(
          "synthesis",
          target: "synthesis-feed",
          partial: "dashboard/situation",
          locals: { situation: situation }
        )
        ActionCable.server.broadcast("airspace", { type: "situation", situation: situation })
      end

      def broadcast_control(payload)
        ActionCable.server.broadcast("airspace", { type: "mode", mode: payload["source"] })
      end
    end
  end
end
