class StubHTTP
  attr_accessor :open_timeout, :read_timeout, :verify_hostname, :hostname
  attr_reader :captured_request

  def initialize(response)
    @response = response
  end

  def request(req)
    @captured_request = req
    @response
  end
end

module StubHTTPHelpers
  def stub_http_api(response_class: Net::HTTPOK, code: "200", body: "ok")
    response = response_class.new("1.1", code, "")
    response.stubs(:body).returns(body)
    stub_http = StubHTTP.new(response)
    Net::HTTP.stubs(:start).yields(stub_http).returns(response)
    stub_http
  end

  def stub_http_failure(error_class: SocketError, message: "connection refused")
    Net::HTTP.stubs(:start).raises(error_class, message)
  end
end
