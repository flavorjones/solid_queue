# frozen_string_literal: true

module SolidQueue::Processes
  module Standby
    extend ActiveSupport::Concern

    delegate :on_active_zone, to: :replication_coordinator
    delegate :on_passive_zone, to: :replication_coordinator
    delegate :active_zone?, to: :replication_coordinator

    def replication_coordinator
      Rails.application.config.replication_coordinator
    end

    included do
      on_start { |process| process.replication_coordinator.start_monitoring }
      on_stop { |process| process.replication_coordinator.stop_monitoring }
    end
  end
end
