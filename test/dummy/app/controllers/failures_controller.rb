class FailuresController < ActionController::Base
  def raise_error
    raise "failure inside a request"
  end

  def report_error
    Rails.error.report RuntimeError.new("reported inside a request"), handled: true, severity: :warning
    head :ok
  end
end
