require "test_helper"

class Admin::InvoicesControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "admin",
          "changeme"
        )
    }
  end

  # --- GET /admin/invoices ---

  test "GET /admin/invoicesは請求書一覧を表示する" do
    # Arrange
    invoices(:open_invoice)

    # Act
    get admin_invoices_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/invoicesはステータスでフィルタリングできる" do
    # Act
    get admin_invoices_path,
        params: {
          status: "open"
        },
        headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/invoicesは認証なしで401を返す" do
    # Act
    get admin_invoices_path

    # Assert
    assert_response :unauthorized
  end

  # --- GET /admin/invoices/new ---

  test "GET /admin/invoices/newは新規請求書フォームを表示する" do
    # Act
    get new_admin_invoice_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  # --- POST /admin/invoices ---

  test "POST /admin/invoicesは有効なパラメータで請求書を作成する" do
    # Arrange
    va = virtual_accounts(:test_va)

    # Act
    assert_difference("Invoice.count", 1) do
      post admin_invoices_path,
           params: {
             invoice: {
               virtual_account_id: va.id,
               amount: 50_000,
               description: "テスト請求",
               due_date: Date.current + 30
             }
           },
           headers: admin_auth_headers
    end

    # Assert
    assert_redirected_to admin_invoices_path
  end

  test "POST /admin/invoicesは無効なパラメータで422を返す" do
    # Arrange
    va = virtual_accounts(:test_va)

    # Act
    post admin_invoices_path,
         params: {
           invoice: {
             virtual_account_id: va.id,
             amount: 0, # 無効: 0以下
             description: "テスト"
           }
         },
         headers: admin_auth_headers

    # Assert
    assert_response :unprocessable_entity
  end

  # --- GET /admin/invoices/:id/edit ---

  test "GET /admin/invoices/:id/editは編集フォームを表示する" do
    # Arrange
    invoice = invoices(:open_invoice)

    # Act
    get edit_admin_invoice_path(invoice), headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  # --- PATCH /admin/invoices/:id ---

  test "PATCH /admin/invoices/:idは有効なパラメータで請求書を更新する" do
    # Arrange
    invoice = invoices(:open_invoice)

    # Act
    patch admin_invoice_path(invoice),
          params: {
            invoice: {
              description: "更新されたテスト請求"
            }
          },
          headers: admin_auth_headers

    # Assert
    assert_redirected_to admin_invoices_path
    invoice.reload
    assert_equal "更新されたテスト請求", invoice.description
  end

  test "PATCH /admin/invoices/:idは無効なパラメータで422を返す" do
    # Arrange
    invoice = invoices(:open_invoice)

    # Act
    patch admin_invoice_path(invoice),
          params: {
            invoice: {
              amount: 0 # 無効: 0以下
            }
          },
          headers: admin_auth_headers

    # Assert
    assert_response :unprocessable_entity
  end

  # --- DELETE /admin/invoices/:id ---

  test "DELETE /admin/invoices/:idは請求書を削除する" do
    # Arrange
    invoice = invoices(:open_invoice)

    # Act
    assert_difference("Invoice.count", -1) do
      delete admin_invoice_path(invoice), headers: admin_auth_headers
    end

    # Assert
    assert_redirected_to admin_invoices_path
  end
end
