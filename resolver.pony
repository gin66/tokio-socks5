use "net"
use "logger"

type InetAddr is (String | Array[U8])

actor Resolver
    let _logger: Logger[String]

    new create(logger: Logger[String]) =>
        _logger = logger

    be connect_to(conn: TCPConnection tag,
            addr: InetAddr iso,port: U16,
            socks_reply: Array[U8] iso) =>
        _logger(Info) and _logger.log("Called connect_to")
        match consume addr
        |    let ip4 : Array[U8] =>
                try
                    _logger(Info) and _logger.log(
                            ip4(0)?.string()+"."+ip4(1)?.string()
                            +"."+ip4(2)?.string()+"."+ip4(3)?.string()
                            +":"+port.string())
                end
        |    let host: String =>
                _logger(Info) and _logger.log(host)
        end
        conn.set_notify(ForwardTCPConnectionNotify(this,_logger))
        conn.write(consume socks_reply)

    be resolve() =>
        None