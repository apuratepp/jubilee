require 'test_helper'
require 'timeout'
require 'socket'
class TestResponse < MiniTest::Unit::TestCase
  def setup
    @valid_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @close_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Close\r\n\r\n"
    @http10_request = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    @keep_request = "GET / HTTP/1.0\r\nHost: test.com\r\nContent-Type: text/plain\r\nConnection: Keep-Alive\r\n\r\n"

    @valid_post = "POST / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
    @valid_no_body = "GET / HTTP/1.1\r\nHost: test.com\r\nX-Status: 204\r\nContent-Type: text/plain\r\n\r\n"

    @headers = { "X-Header" => "Works" }
    @body = ["Hello"]

    @host = "127.0.0.1"
    @port = 8080

  end

  def teardown
    @client.close if @client
    @server.stop if @server
    sleep 0.1
  end

  def lines(count, s=@client)
    str = ""
    timeout(5) do
      count.times { str << s.gets }
    end
    str
  end

  def valid_response(size)
    Regexp.new("HTTP/1.1 200 OK\r\nX-Header: Works\r\n(.*?\r\n)*?Content-Length: #{size}\r\nConnection: keep-alive\r\nDate(.*?)\r\n\r\n", true)
  end

  def test_one_with_content_length
    start_server
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_match valid_response(sz), lines(7)
    assert_equal "Hello", @client.read(5)
  end

  def test_two_back_to_back
    start_server
    @client << @valid_request
    sz = @body[0].size.to_s

    assert_match valid_response(sz), lines(7)
    assert_equal "Hello", @client.read(5)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_match valid_response(sz), lines(7)
    assert_equal "Hello", @client.read(5)
  end

  def test_post_then_get
    start_server
    @client << @valid_post
    sz = @body[0].size.to_s

    assert_match valid_response(sz), lines(7)
    assert_equal "Hello", @client.read(5)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_match valid_response(sz), lines(7)
    assert_equal "Hello", @client.read(5)
  end

  def test_no_body_then_get
    start_server
    @client << @valid_no_body
    assert_match %r{HTTP/1.1 204 No Content\r\nX-Header: Works\r\nConnection: keep-alive\r\n(.*?\r\n)*?\r\n}, lines(6)

    @client << @valid_request
    sz = @body[0].size.to_s

    assert_match %r{HTTP/1.1 200 OK\r\nX-Header: Works\r\nServer: Jubilee\(\d\.\d\.\d\)\r\nContent-Length: #{sz}\r\nConnection: keep-alive\r\n(.*?\r\n)*?\r\n}, lines(7)
    assert_equal "Hello", @client.read(5)
  end

  def test_chunked
    start_server("chunked")

    @client << @valid_request

    assert_match %r{HTTP/1.1 200 OK\r\nX-Header: Works\r\nServer: Jubilee\(\d\.\d\.\d\)\r\nTransfer-Encoding: chunked\r\nDate(.*?)\r\n\r\n5\r\nHello\r\n7\r\nChunked\r\n0\r\n\r\n}, lines(13)
  end

  def test_no_chunked_in_http10
    start_server("chunked")

    @client << @http10_request

    assert_match %r{HTTP/1.0 200 OK\r\nX-Header: Works\r\nConnection: close\r\n\r\n}, lines(5)
    assert_equal "HelloChunked", @client.read
  end

  def test_hex
    skip
    str = "This is longer and will be in hex"
    @body << str

    @client << @valid_request

    assert_equal "HTTP/1.1 200 OK\r\nX-Header: Works\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n#{str.size.to_s(16)}\r\n#{str}\r\n0\r\n\r\n", lines(10)

  end

  def test_client11_close
    start_server
    @client << @close_request
    sz = @body[0].size.to_s

    assert_match %r{HTTP/1.1 200 OK\r\nX-Header: Works\r\nServer: Jubilee\(\d\.\d\.\d\)\r\nContent-Length: #{sz}\r\nConnection: close\r\n\r\n}, lines(7)
    assert_equal "Hello", @client.read(5)
  end

  def start_server(ru='persistent1')
    config = Jubilee::Configuration.new(rackup: File.expand_path("../../apps/#{ru}.ru", __FILE__), instances: 1)
    @server = Jubilee::Server.new(config.options)
    q = Queue.new
    @server.start{ q << 1 }
    q.pop
    @client = TCPSocket.new @host, @port
  end
end