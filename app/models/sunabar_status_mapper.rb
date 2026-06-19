class SunabarStatusMapper
  MAPPING = {
    "AcceptedToBank" => "requested",
    "AwaitingApproval" => "awaiting_approval",
    "Approved" => "approved",
    "Settled" => "settled",
    "Failed" => "failed",
    "Rejected" => "failed"
  }.freeze

  def self.map(sunabar_status)
    MAPPING.fetch(sunabar_status) do
      raise ArgumentError, "不明なsunabarステータス: #{sunabar_status}"
    end
  end

  def self.terminal?(internal_status)
    %w[settled failed].include?(internal_status)
  end
end
