use "net"
use "logger"

class SocksTCPConnectionNotify is TCPConnectionNotify
  let _logger: Logger[String]

  new iso create(logger: Logger[String]) =>
    _logger = logger

  fun ref received(
    conn: TCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _logger(Info) and _logger.log("Received data")
    conn.write(String.from_array(consume data))
    true

  fun ref throttled(conn: TCPConnection ref) =>
    None

  fun ref unthrottled(conn: TCPConnection ref) =>
    None

  fun ref accepted(conn: TCPConnection ref) =>
    None

  fun ref connect_failed(conn: TCPConnection ref) =>
    None

  fun ref closed(conn: TCPConnection ref) =>
    _logger(Info) and _logger.log("Connection closed")

class SocksTCPListenNotify is TCPListenNotify
  let _logger: Logger[String]

  new iso create(logger: Logger[String]) =>
    _logger = logger

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    SocksTCPConnectionNotify(_logger)

  fun ref listening(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Successfully bound to address")

  fun ref not_listening(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Cannot bind to listen address")

  fun ref closed(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Successfully closed TCP listeners")
