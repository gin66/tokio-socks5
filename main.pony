use "net"
use "logger"
use "files"
use "ini"

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
      logger(Info) and logger.log("Load ini-file")
      let ini_file = File(FilePath(env.root as AmbientAuth, "config.ini")?)
      let sections = IniParse(ini_file.lines())?
      for section in sections.keys() do
        env.out.print("Section name is: " + section)
        for key in sections(section)?.keys() do
          env.out.print(key + " = " + sections(section)?(key)?)
        end
      end

      let auth = env.root as AmbientAuth

      logger(Info) and logger.log("Load geo ip database")
      let ipdb = IpDBfactory.make(FilePath(auth,"dbip-country-2017-12.csv")?,logger)?
      ipdb.locate(1047275918)

      let resolver = Resolver(auth,logger)
      UDPSocket(auth, MyUDPNotify, "", "8989")
      TCPListener(auth,
        recover SocksTCPListenNotify(resolver,logger) end, 
        "127.0.0.1", "8989" 
        where init_size=16384,max_size = 16384)
    end
