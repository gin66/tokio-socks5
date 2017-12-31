use "net"
use "logger"

class InetAddrPort is Stringable
    let host: String
    var ip: (U8,U8,U8,U8) = (0,0,0,0)
    let port: U16

    new iso create_from_string(host': String,port':U16) =>
        host = host'
        port = port'

    new iso create(ip': (U8,U8,U8,U8),port':U16) =>
        ip   = ip'
        port = port'
        (let ip1,let ip2,let ip3,let ip4) = ip'
        host = ip1.string()+"."+ip2.string()+"."+ip3.string()+"."+ip4.string()

    fun box host_str() : String iso^ =>
        host.string()

    fun box port_str() : String iso^ =>
        port.string()

    fun box string() : String iso^ =>
        (host + ":" + port.string()).string()

actor Resolver
    let _logger: Logger[String]
    let _auth: (AmbientAuth val | NetAuth val | TCPAuth val | 
                TCPConnectAuth val)

    new create(auth: (AmbientAuth val | NetAuth val | TCPAuth val | 
               TCPConnectAuth val),
               logger: Logger[String]) =>
        _auth   = auth
        _logger = logger

    be connect_to(conn: TCPConnection tag,
            addr: InetAddrPort iso,port: U16,
            socks_reply: Array[U8] iso) =>
        _logger(Info) and _logger.log("Called connect_to "+addr.string())
        conn.mute()
        let conn_peer = TCPConnection(_auth,
                            DirectForwardTCPConnectionNotify(conn,consume socks_reply,_logger),
                            addr.host_str(),
                            addr.port_str()
                            where init_size=16384,max_size = 16384)
        let empty: Array[U8] iso = recover iso Array[U8]() end
        conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer,consume empty,_logger))
        conn.unmute()

    be resolve() =>
        None