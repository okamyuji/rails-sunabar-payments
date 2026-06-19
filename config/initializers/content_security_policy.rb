Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data
    policy.img_src :self, :data
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.base_uri :self
    policy.frame_ancestors :none
  end

  config.content_security_policy_nonce_generator = ->(_request) do
    SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]
end
