require "test_helper"
require "tmpdir"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders the fixture-backed dashboard" do
    get root_path

    assert_response :success
    assert_select "h1", "FlightWatch"
    assert_select "a[href=?]", credits_path, text: "Credits"
    assert_select "#anomaly-feed article", minimum: 3
    assert_select "#synthesis-feed article", minimum: 1
    assert_includes response.body, "KBOS"
  end

  test "writes mode changes to the workspace file bus" do
    Dir.mktmpdir do |dir|
      previous = ENV["FLIGHTWATCH_WORKSPACE"]
      ENV["FLIGHTWATCH_WORKSPACE"] = dir

      post mode_path, params: { source: "realtime" }, as: :json

      assert_response :success
      mode_file = Pathname.new(dir).join("control", "mode.json")
      assert mode_file.exist?
      assert_equal "realtime", JSON.parse(File.read(mode_file))["source"]
    ensure
      ENV["FLIGHTWATCH_WORKSPACE"] = previous
    end
  end
end
