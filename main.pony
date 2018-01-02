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
      let auth = env.root as AmbientAuth

      // Only clients need to load ip database !!!
      let ipdb = IpDB(logger)
      let promise = ipdb.locate(1047275918)
      promise.next[None]({(ans:String) => 
            logger(Info) and logger.log("Located: " + ans.string()) })

      ipdb.start_load(FilePath(auth,"dbip-country-2017-12.csv")?)

      logger(Info) and logger.log("Load ini-file")
      let ini_file = File(FilePath(auth, "config.ini")?)
      let sections = IniParse(ini_file.lines())?
      for (id,name) in sections("Nodes")?.pairs() do
        env.out.print("NODE ID=" + id + " is " + name)
        let id_num = id.u8()?
        if sections.contains(name) then
          for (key,value) in sections(name)?.pairs() do
            match key
            | "UDPAddresses" =>
                for addr in value.split(",").values() do
                  let ia = InetAddrPort.create_from_host_port(addr)?
                  env.out.print("    UDP " + ia.string())
                end
            | "TCPAddresses" =>
                for addr in value.split(",").values() do
                  let ia = InetAddrPort.create_from_host_port(addr)?
                  env.out.print("    TCP " + ia.string())
                end
            end
          end
        else
          env.out.print("    No section for this node")
          error
        end
      end

      let resolver = Resolver(auth,logger)
      UDPSocket(auth, MyUDPNotify, "", "8989")
      TCPListener(auth,
        recover SocksTCPListenNotify(resolver,logger) end, 
        "127.0.0.1", "8989" 
        where init_size=16384,max_size = 16384)
    end
