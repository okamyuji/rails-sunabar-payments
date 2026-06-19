module Admin
  class InvoicesController < BaseController
    def index
      invoices = Invoice.all.by_status(params[:status]).order(created_at: :desc)
      @pagy, @invoices = pagy(invoices)
    end

    def new
      @invoice = Invoice.new
    end

    def create
      @invoice = Invoice.new(invoice_params)
      if @invoice.save
        redirect_to admin_invoices_path, notice: "請求書を作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @invoice = Invoice.find(params[:id])
    end

    def update
      @invoice = Invoice.find(params[:id])
      if @invoice.update(invoice_params)
        redirect_to admin_invoices_path, notice: "請求書を更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Invoice.find(params[:id]).destroy!
      redirect_to admin_invoices_path, notice: "請求書を削除しました"
    end

    private

    def invoice_params
      params.require(:invoice).permit(
        :virtual_account_id,
        :amount,
        :description,
        :due_date
      )
    end
  end
end
