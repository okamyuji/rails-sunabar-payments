require "test_helper"

module Api
  class ErrorRaisingController < BaseController
    ERRORS = {
      "not_found" => -> { ActiveRecord::RecordNotFound.new },
      "unprocessable" => -> do
        invoice = Invoice.new
        invoice.errors.add(:base, "金額が不正です")
        ActiveRecord::RecordInvalid.new(invoice)
      end,
      "stale_object" => -> { ActiveRecord::StaleObjectError.new },
      "invalid_reference" => -> { ActiveRecord::InvalidForeignKey.new("fk") },
      "conflict" => -> do
        HasStatusMachine::InvalidTransition.new("pendingからsettledへは遷移できません")
      end
    }.freeze

    def show
      raise ERRORS.fetch(params[:id]).call
    end
  end
end

class Api::BaseControllerTest < ActionDispatch::IntegrationTest
  # with_routing はブロック終了時に統合セッションを破棄するので、応答はブロック内で取り出す
  def request_error(kind)
    with_routing do |set|
      set.draw { get "/api/errors/:id", to: "api/error_raising#show" }
      get "/api/errors/#{kind}", as: :json
      [response.status, JSON.parse(response.body)]
    end
  end

  test "RecordNotFoundは404とnot_foundを返す" do
    status, body = request_error("not_found")

    assert_equal 404, status
    assert_equal(
      { "error" => { "code" => "not_found", "message" => "リソースが見つかりません" } },
      body
    )
  end

  test "RecordInvalidは422と例外メッセージ付きvalidation_errorを返す" do
    status, body = request_error("unprocessable")

    assert_equal 422, status
    expected_message =
      Api::ErrorRaisingController::ERRORS.fetch("unprocessable").call.message
    assert_includes expected_message, "金額が不正です"
    assert_equal(
      {
        "error" => {
          "code" => "validation_error",
          "message" => expected_message
        }
      },
      body
    )
  end

  test "StaleObjectErrorは409とstale_objectを返す" do
    status, body = request_error("stale_object")

    assert_equal 409, status
    assert_equal(
      {
        "error" => {
          "code" => "stale_object",
          "message" => "リソースが更新されています。再取得してください"
        }
      },
      body
    )
  end

  test "InvalidForeignKeyは422と参照先エラーのvalidation_errorを返す" do
    status, body = request_error("invalid_reference")

    assert_equal 422, status
    assert_equal(
      {
        "error" => {
          "code" => "validation_error",
          "message" => "参照先が存在しません"
        }
      },
      body
    )
  end

  test "InvalidTransitionは409と例外メッセージ付きconflictを返す" do
    status, body = request_error("conflict")

    assert_equal 409, status
    assert_equal(
      {
        "error" => {
          "code" => "conflict",
          "message" => "pendingからsettledへは遷移できません"
        }
      },
      body
    )
  end

  test "APIトークンが一致しないと401とunauthorizedを返す" do
    original = ENV["API_TOKEN"]
    ENV["API_TOKEN"] = "expected-token"

    get api_accounts_path,
        headers: {
          "Authorization" => "Bearer wrong-token"
        },
        as: :json

    assert_equal 401, response.status
    assert_equal(
      { "error" => { "code" => "unauthorized", "message" => "無効なAPIトークン" } },
      JSON.parse(response.body)
    )
  ensure
    ENV["API_TOKEN"] = original
  end
end
