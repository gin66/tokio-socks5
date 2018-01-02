use "net"
use "logger"
use "files"
use "ini"
use "collections"

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
      ipdb.start_load(FilePath(auth,"dbip-country-2017-12.csv")?)

      let resolver = Resolver(auth,logger)

      logger(Info) and logger.log("Load ini-file")
      let ini_file = File(FilePath(auth, "config.ini")?)
      let sections = IniParse(ini_file.lines())?
      let myID = sections("Self")?("myID")?.u8()?
      // Loop twice over the Nodes section. 
      // First for other nodes and then for myself
      let nodes = HashMap[U8,Node tag,HashIs[U8]]
      for self in [false;true].values() do
        for (id,name) in sections("Nodes")?.pairs() do
          let id_num = id.u8()?
          if (id_num == myID) == self then
            if sections.contains(name) then
              let node = NodeBuilder(ipdb,id_num,name,logger)
              for (key,value) in sections(name)?.pairs() do
                match key
                | "UDPAddresses" =>
                    for addr in value.split(",").values() do
                      let ia = InetAddrPort.create_from_host_port(addr)?
                      node.static_udp(consume ia)
                    end
                | "TCPAddresses" =>
                    for addr in value.split(",").values() do
                      let ia = InetAddrPort.create_from_host_port(addr)?
                      node.static_tcp(consume ia)
                    end
                | "Socks5Address" =>
                    let ia = InetAddrPort.create_from_host_port(value)?
                    TCPListener(auth,
                      recover SocksTCPListenNotify(resolver,logger) end, 
                      ia.host_str(), ia.port_str() 
                      where init_size=16384,max_size = 16384)
                | "SocksProxy" =>
                    if self then
                      for proxy in value.split(",").values() do
                        let ad_id = proxy.split_by("->")
                        let addr  = ad_id(0)?
                        let to_id = ad_id(1)?.u8()?
                        try
                          let node_actor = nodes(to_id)?
                          let ia = InetAddrPort.create_from_host_port(addr)?
                          node_actor.add_socks_proxy(consume ia)
                        else
                          env.out.print("Cannot find node for this proxy:"+addr.string())
                        end
                      end
                    end
                end
            end
            let node_actor = node.build()
              nodes.update(id_num,node_actor)
            else
              env.out.print("    No section for this node")
              error
            end
          end
        end
      end

      UDPSocket(auth, MyUDPNotify, "", "8989")
    end
