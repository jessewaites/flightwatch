class StaticPagesController < ApplicationController
  def credits
  end

  def evals
    @benchmark = read_json_artifact("benchmark.json")
    @evals = read_json_artifact("evals/evals.json")
  end

  private

  def read_json_artifact(relative_path)
    path = Rails.root.join("..", relative_path)
    return {} unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end
end
