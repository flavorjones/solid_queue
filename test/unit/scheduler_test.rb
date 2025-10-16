require "test_helper"
require "active_support/testing/replication_coordinator"

class SchedulerTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "recurring schedule" do
    recurring_tasks = { example_task: { class: "AddToBufferJob", schedule: "every hour", args: 42 } }
    scheduler = SolidQueue::Scheduler.new(recurring_tasks: recurring_tasks).tap(&:start)

    wait_for_registered_processes(1, timeout: 1.second)

    process = SolidQueue::Process.first
    assert_equal "Scheduler", process.kind

    assert_metadata process, recurring_schedule: [ "example_task" ]
  ensure
    scheduler&.stop
  end

  test "unschedules recurring tasks on change to inactive zone" do
    @was_rc, Rails.application.config.replication_coordinator = Rails.application.config.replication_coordinator, ActiveSupport::Testing::ReplicationCoordinator.new(true, polling_interval: 0.1.seconds)

    recurring_tasks = { example_task: { class: "AddToBufferJob", schedule: "every hour", args: 42 } }
    scheduler = SolidQueue::Scheduler.new(recurring_tasks: recurring_tasks).tap(&:start)

    wait_for_registered_processes(1, timeout: 1.second)
    scheduler.expects(:unschedule_recurring_tasks).twice # once on change, once on shutdown

    Rails.application.config.replication_coordinator.set_next_active_zone(false)
    sleep 0.2.seconds
  ensure
    scheduler&.stop
    Rails.application.config.replication_coordinator = @was_rc
  end

  test "schedules recurring tasks on change to active zone" do
    @was_rc, Rails.application.config.replication_coordinator = Rails.application.config.replication_coordinator, ActiveSupport::Testing::ReplicationCoordinator.new(false, polling_interval: 0.1.seconds)

    recurring_tasks = { example_task: { class: "AddToBufferJob", schedule: "every hour", args: 42 } }
    scheduler = SolidQueue::Scheduler.new(recurring_tasks: recurring_tasks).tap(&:start)

    wait_for_registered_processes(1, timeout: 1.second)
    scheduler.expects(:schedule_recurring_tasks).once # once on change, once on shutdown

    Rails.application.config.replication_coordinator.set_next_active_zone(true)
    sleep 0.2.seconds
  ensure
    scheduler&.stop
    Rails.application.config.replication_coordinator = @was_rc
  end

  test "run more than one instance of the scheduler with recurring tasks" do
    recurring_tasks = { example_task: { class: "AddToBufferJob", schedule: "every second", args: 42 } }
    schedulers = 2.times.collect do
      SolidQueue::Scheduler.new(recurring_tasks: recurring_tasks)
    end

    schedulers.each(&:start)
    sleep 2
    schedulers.each(&:stop)

    assert_equal SolidQueue::Job.count, SolidQueue::RecurringExecution.count
    run_at_times = SolidQueue::RecurringExecution.all.map(&:run_at).sort
    0.upto(run_at_times.length - 2) do |i|
      assert_equal 1, run_at_times[i + 1] - run_at_times[i]
    end
  end
end
