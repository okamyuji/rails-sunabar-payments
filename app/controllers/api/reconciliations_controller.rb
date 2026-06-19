module Api
  class ReconciliationsController < BaseController
    def run
      ReconcileJob.perform_later
      render json: { message: "消込ジョブを開始しました" }
    end
  end
end
