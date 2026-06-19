require "test_helper"

class NotificationSenderTest < ActiveSupport::TestCase
  # --- send_notification ---

  test "send_notificationはログに記録する" do
    # Arrange
    sender = NotificationSender.new

    # Act & Assert - 例外が発生しないことを確認
    assert_nothing_raised do
      sender.send_notification(
        event_type: "TransferSettled",
        payload: {
          transfer_id: "test-id"
        }
      )
    end
  end

  test "send_notificationはevent_typeとpayloadをログに含める" do
    # Arrange
    sender = NotificationSender.new
    log_output = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(log_output)

    # Act
    sender.send_notification(
      event_type: "TransferFailed",
      payload: {
        transfer_id: "test-id-2"
      }
    )

    # Assert
    log_content = log_output.string
    assert_match(/notification_sent/, log_content)
    assert_match(/TransferFailed/, log_content)
  ensure
    Rails.logger = ActiveSupport::Logger.new(STDOUT)
  end
end
