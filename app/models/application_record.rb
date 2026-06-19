class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.uuid_primary_key
    attribute :id, :uuid_binary
    before_create :assign_uuid_v7
  end

  def assign_uuid_v7
    self.id ||= SecureRandom.uuid_v7
  end

  def id_for_payload
    UuidBinaryType.to_uuid_string(id_before_type_cast)
  end
end
