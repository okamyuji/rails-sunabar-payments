module HasStatusMachine
  extend ActiveSupport::Concern

  class InvalidTransition < StandardError
  end

  class_methods do
    def define_transitions(map)
      @status_transitions =
        map.transform_keys(&:to_s).transform_values { |v| v.map(&:to_s) }
    end

    def status_transitions
      @status_transitions || {}
    end
  end

  def transition_to!(new_status)
    allowed = self.class.status_transitions[status]
    unless allowed&.include?(new_status.to_s)
      raise InvalidTransition,
            "#{self.class.name}: #{status}から#{new_status}への遷移は許可されていません"
    end
    update!(status: new_status)
  end
end
