module Api
  class BaseController < ActionController::API
    include Pagy::Method

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
    rescue_from ActiveRecord::StaleObjectError, with: :stale_object
    rescue_from ActiveRecord::InvalidForeignKey, with: :invalid_reference
    rescue_from HasStatusMachine::InvalidTransition, with: :conflict

    before_action :authenticate_api_token!
    before_action :set_request_id

    private

    def authenticate_api_token!
      expected = ENV["API_TOKEN"]
      return if expected.blank? && (Rails.env.development? || Rails.env.test?)
      raise "API_TOKEN未設定" if expected.blank?

      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      if ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
        return
      end

      render json: {
               error: {
                 code: "unauthorized",
                 message: "無効なAPIトークン"
               }
             },
             status: :unauthorized
    end

    def not_found(_e)
      render json: {
               error: {
                 code: "not_found",
                 message: "リソースが見つかりません"
               }
             },
             status: :not_found
    end

    def unprocessable(e)
      render json: {
               error: {
                 code: "validation_error",
                 message: e.message
               }
             },
             status: :unprocessable_entity
    end

    def stale_object(_e)
      render json: {
               error: {
                 code: "stale_object",
                 message: "リソースが更新されています。再取得してください"
               }
             },
             status: :conflict
    end

    def invalid_reference(_e)
      render json: {
               error: {
                 code: "validation_error",
                 message: "参照先が存在しません"
               }
             },
             status: :unprocessable_entity
    end

    def conflict(e)
      render json: {
               error: {
                 code: "conflict",
                 message: e.message
               }
             },
             status: :conflict
    end

    def set_request_id
      Thread.current[:request_id] = request.request_id
    end

    def paginate(scope)
      per_page = [params.fetch(:per_page, 25).to_i, 100].min
      pagy, records = pagy(scope, limit: per_page)
      {
        data: records,
        pagination: {
          page: pagy.page,
          per_page: pagy.limit,
          total_count: pagy.count,
          total_pages: pagy.pages
        }
      }
    end
  end
end
