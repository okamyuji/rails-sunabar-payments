require "test_helper"

class UuidBinaryTypeTest < ActiveSupport::TestCase
  def setup
    @type = UuidBinaryType.new
    @uuid_string = "01935e1b-2c3d-71e5-f6a7-b8c9d0e1f2a3"
    @uuid_hex = "01935e1b2c3d71e5f6a7b8c9d0e1f2a3"
    @uuid_binary = [@uuid_hex].pack("H*")
  end

  # --- cast ---

  test "castはnilに対してnilを返す" do
    assert_nil @type.cast(nil)
  end

  test "castは16バイトのバイナリをそのまま返す" do
    # Arrange
    binary = @uuid_binary

    # Act
    result = @type.cast(binary)

    # Assert
    assert_equal binary, result
    assert_equal 16, result.bytesize
  end

  test "castはUUID文字列をバイナリに変換する" do
    # Arrange & Act
    result = @type.cast(@uuid_string)

    # Assert
    assert_equal 16, result.bytesize
    assert_equal @uuid_binary, result
  end

  test "castはハイフンなしのUUID文字列もバイナリに変換する" do
    # Arrange & Act
    result = @type.cast(@uuid_hex)

    # Assert
    assert_equal 16, result.bytesize
    assert_equal @uuid_binary, result
  end

  # --- deserialize ---

  test "deserializeはnilに対してnilを返す" do
    assert_nil @type.deserialize(nil)
  end

  test "deserializeはバイナリをUUID文字列に変換する" do
    # Arrange & Act
    result = @type.deserialize(@uuid_binary)

    # Assert
    assert_equal @uuid_string, result
  end

  # --- serialize ---

  test "serializeはnilに対してnilを返す" do
    assert_nil @type.serialize(nil)
  end

  test "serializeはUUID文字列をActiveRecord::Type::Binary::Dataに変換する" do
    # Arrange & Act
    result = @type.serialize(@uuid_string)

    # Assert
    assert_instance_of ActiveRecord::Type::Binary::Data, result
  end

  # --- to_uuid_string ---

  test "to_uuid_stringはnilに対してnilを返す" do
    assert_nil UuidBinaryType.to_uuid_string(nil)
  end

  test "to_uuid_stringはバイナリをハイフン付きUUID文字列に変換する" do
    # Arrange & Act
    result = UuidBinaryType.to_uuid_string(@uuid_binary)

    # Assert
    assert_equal @uuid_string, result
    # フォーマット確認: 8-4-4-4-12
    assert_match(
      /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
      result
    )
  end

  test "to_uuid_stringはActiveRecord::Type::Binary::Dataも処理する" do
    # Arrange
    data = ActiveRecord::Type::Binary::Data.new(@uuid_binary)

    # Act
    result = UuidBinaryType.to_uuid_string(data)

    # Assert
    assert_equal @uuid_string, result
  end
end
