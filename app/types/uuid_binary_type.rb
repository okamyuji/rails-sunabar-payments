class UuidBinaryType < ActiveRecord::Type::Binary
  def cast(value)
    return nil if value.nil?
    return value if value.is_a?(String) && value.bytesize == 16

    hex = value.to_s.delete("-")
    [hex].pack("H*")
  end

  def deserialize(value)
    return nil if value.nil?

    self.class.to_uuid_string(value)
  end

  def serialize(value)
    binary = cast(value)
    return nil if binary.nil?

    Data.new(binary)
  end

  def self.to_uuid_string(binary)
    return nil if binary.nil?

    raw = binary.is_a?(Data) ? binary.to_s : binary
    hex = raw.unpack1("H*")
    "#{hex[0..7]}-#{hex[8..11]}-#{hex[12..15]}-#{hex[16..19]}-#{hex[20..31]}"
  end
end
