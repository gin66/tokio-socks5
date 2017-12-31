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
        conn.set_notify(ForwardTCPConnectionNotify(this,_logger))
        conn.write(consume socks_reply)

    be resolve() =>
        None