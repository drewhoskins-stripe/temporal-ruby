# Protoc wants all of its generated files on the LOAD_PATH
$LOAD_PATH << File.expand_path('./gen', __dir__)

require 'securerandom'
require 'temporal/configuration'
require 'temporal/execution_options'
require 'temporal/client'
require 'temporal/activity'
require 'temporal/activity/async_token'
require 'temporal/workflow'
require 'temporal/workflow/history'
require 'temporal/workflow/execution_info'
require 'temporal/metrics'

module Temporal
  class << self
    def start_workflow(workflow, *input, **args)
      options = args.delete(:options) || {}
      input << args unless args.empty?

      execution_options = ExecutionOptions.new(workflow, options)
      workflow_id = options[:workflow_id] || SecureRandom.uuid

      response = client.start_workflow_execution(
        namespace: execution_options.namespace,
        workflow_id: workflow_id,
        workflow_name: execution_options.name,
        task_queue: execution_options.task_queue,
        input: input,
        execution_timeout: execution_options.timeouts[:execution],
        task_timeout: execution_options.timeouts[:task],
        workflow_id_reuse_policy: options[:workflow_id_reuse_policy],
        headers: execution_options.headers
      )

      response.run_id
    end

    def register_namespace(name, description = nil)
      client.register_namespace(name: name, description: description)
    end

    def signal_workflow(workflow, signal, workflow_id, run_id, input = nil)
      client.signal_workflow_execution(
        namespace: workflow.namespace, # TODO: allow passing namespace instead
        workflow_id: workflow_id,
        run_id: run_id,
        signal: signal,
        input: input
      )
    end

    def reset_workflow(namespace, workflow_id, run_id, decision_task_id: nil, reason: 'manual reset')
      decision_task_id ||= get_last_completed_decision_task(namespace, workflow_id, run_id)
      raise Error, 'Could not find a completed decision task event' unless decision_task_id

      response = client.reset_workflow_execution(
        namespace: namespace,
        workflow_id: workflow_id,
        run_id: run_id,
        reason: reason,
        decision_task_event_id: decision_task_id
      )

      response.run_id
    end

    def fetch_workflow_execution_info(namespace, workflow_id, run_id)
      response = client.describe_workflow_execution(
        namespace: namespace,
        workflow_id: workflow_id,
        run_id: run_id
      )

      Workflow::ExecutionInfo.generate_from(response.workflow_execution_info)
    end

    def complete_activity(async_token, result = nil)
      details = Activity::AsyncToken.decode(async_token)

      client.respond_activity_task_completed_by_id(
        namespace: details.namespace,
        activity_id: details.activity_id,
        workflow_id: details.workflow_id,
        run_id: details.run_id,
        result: result
      )
    end

    def fail_activity(async_token, exception)
      details = Activity::AsyncToken.decode(async_token)

      client.respond_activity_task_failed_by_id(
        namespace: details.namespace,
        activity_id: details.activity_id,
        workflow_id: details.workflow_id,
        run_id: details.run_id,
        exception: exception
      )
    end

    def configure(&block)
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def logger
      configuration.logger
    end

    def metrics
      @metrics ||= Metrics.new(configuration.metrics_adapter)
    end

    private

    def client
      @client ||= Temporal::Client.generate
    end

    def get_last_completed_decision_task(namespace, workflow_id, run_id)
      history_response = client.get_workflow_execution_history(
        namespace: namespace,
        workflow_id: workflow_id,
        run_id: run_id
      )
      history = Workflow::History.new(history_response.history.events)
      decision_task_event = history.last_completed_decision_task

      decision_task_event&.id
    end
  end
end
