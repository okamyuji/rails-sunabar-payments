class VirtualAccount < ApplicationRecord
  uuid_primary_key

  attribute :account_id, :uuid_binary

  belongs_to :account
  has_many :invoices, dependent: :restrict_with_error
  has_many :incoming_transactions, dependent: :restrict_with_error

  validates :sunabar_va_id, presence: true, uniqueness: true
  validates :va_number, presence: true

  def self.issue!(account:, va_name:, client: SunabarClient.instance)
    response =
      client.issue_virtual_account(
        account_id: account.sunabar_account_id,
        va_name: va_name
      )
    create!(
      account: account,
      sunabar_va_id: response[:vaId],
      va_number: response[:vaNumber],
      va_name: va_name
    )
  end
end
