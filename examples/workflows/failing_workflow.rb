class FailingWorkflow < Temporal::Workflow
  class SomeError < StandardError; end
  class SomeComplexError < StandardError
    def initialize(message, some_context)
      super(message)
      @some_context = some_context
    end
  end

  def execute(error_context = nil)
    if error_context
      raise SomeComplexError, 'Whoopsie', error_context
    else
      raise SomeError, 'Whoops'
    end
  end
end
