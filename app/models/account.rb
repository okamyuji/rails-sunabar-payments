class Account < ApplicationRecord
  uuid_primary_key

  has_many :virtual_accounts, dependent: :destroy
  has_many :transfers, dependent: :restrict_with_error

  validates :sunabar_account_id, presence: true, uniqueness: true
  validates :account_number, presence: true
  validates :branch_code, presence: true

  def self.sync!(client: SunabarClient.instance)
    response = client.list_accounts
    response[:accounts].each do |acc|
      record = find_or_initialize_by(sunabar_account_id: acc[:accountId])
      record.assign_attributes(
        account_number: acc[:accountNumber],
        branch_code: acc[:branchCode],
        account_name: acc[:accountName],
        synced_at: Time.current
      )
      record.save!
    end
  end

  def fetch_balance(client: SunabarClient.instance)
    client.get_balance(account_id: sunabar_account_id)
  end
end
