module Flightwatch
  class WorkspaceListener
    class << self
      def start
        return if defined?(@listener) && @listener

        watched_paths = %w[flags verdicts situations control].map { |dir| Workspace.path.join(dir) }
        watched_paths.each { |dir| FileUtils.mkdir_p(dir) }

        @listener = Listen.to(*watched_paths.map(&:to_s), only: /\.json$/) do |modified, added, _removed|
          (added + modified).each { |path| Flightwatch::FileBusBroadcaster.broadcast(path) }
        end

        @listener.start
      end
    end
  end
end
