use "net"
use "logger"
use "files"

class MyUDPNotify is UDPNotify
  fun ref received(
    sock: UDPSocket ref,
    data: Array[U8] iso,
    from: NetAddress)
  =>
    sock.write(consume data, from)

  fun ref not_listening(sock: UDPSocket ref) =>
    None

primitive MyLogFormatter is LogFormatter
  fun apply(msg: String, loc: SourceLoc): String =>
    let file_name: String = loc.file()
    let file_linenum: String  = loc.line().string()
    let file_linepos: String  = loc.pos().string()

    (recover String(file_name.size()
      + file_linenum.size()
      + file_linepos.size()
      + msg.size()
      + 4)
    end)
     .> append(Path.base(file_name))
     .> append(":")
     .> append(file_linenum)
     .> append(":")
     .> append(file_linepos)
     .> append(": ")
     .> append(msg)

actor Main
  new create(env: Env) =>
    let logger = StringLogger(
      Info,
      env.out,
      MyLogFormatter)
    try
      let auth = env.root as AmbientAuth
      let resolver = Resolver(auth,logger)
      logger(Info) and logger.log("my info message")
      UDPSocket(auth, MyUDPNotify, "", "8989")
      TCPListener(auth,
        recover SocksTCPListenNotify(resolver,logger) end, "", "8989" where max_size = 1492)
    end
