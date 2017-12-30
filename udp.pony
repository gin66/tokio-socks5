use "net"
use "logger"

class MyUDPNotify is UDPNotify
  fun ref received(
    sock: UDPSocket ref,
    data: Array[U8] iso,
    from: NetAddress)
  =>
    sock.write(consume data, from)

  fun ref not_listening(sock: UDPSocket ref) =>
    None

actor Main
  new create(env: Env) =>
    let logger = StringLogger(
      Info,
      env.out)
    logger(Info) and logger.log("my info message")
    try
      UDPSocket(env.root as AmbientAuth, MyUDPNotify, "", "8989")
      TCPListener(env.root as AmbientAuth,
        recover SocksTCPListenNotify(logger) end, "", "8989")
    end
