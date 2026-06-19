require_relative "../../app/types/uuid_binary_type"
ActiveRecord::Type.register(:uuid_binary, UuidBinaryType)
