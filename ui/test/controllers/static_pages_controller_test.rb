require "test_helper"

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  test "renders the credits page" do
    get credits_path

    assert_response :success
    assert_select "h1", "Jesse Waites"
    assert_select "img[alt=?]", "QR code for Jesse Waites on LinkedIn"
    assert_includes response.body, "linkedin.com/in/jessewaites"
  end

  test "renders the evals page" do
    get evals_path

    assert_response :success
    assert_select "h1", "Evals"
    assert_select "h2", "With skill vs. no skill"
    assert_includes response.body, "skills/flight-investigation/SKILL.md"
  end
end
