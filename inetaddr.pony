class InetAddrPort is Stringable
    let host: String
    var ip: (U8,U8,U8,U8) = (0,0,0,0)
    let port: U16

    new iso create_from_string(host': String,port':U16) =>
        host = host'
        port = port'
        check_ip()

    new iso create_from_host_port(host_port: String) ? =>
        let hp = host_port.split(":")
        host = hp(0)?
        port = hp(1)?.u16()?
        check_ip()

    new iso create(ip': (U8,U8,U8,U8),port':U16) =>
        ip   = ip'
        port = port'
        (let ip1,let ip2,let ip3,let ip4) = ip'
        host = ip1.string()+"."+ip2.string()+"."+ip3.string()+"."+ip4.string()

    fun ref check_ip() =>
        let parts = host.split(".")
        if parts.size() == 4 then
            try
                let ip1 = parts(0)?.u8()?
                let ip2 = parts(1)?.u8()?
                let ip3 = parts(2)?.u8()?
                let ip4 = parts(3)?.u8()?
                ip  = (ip1,ip2,ip3,ip4)
            end
        end

    fun box u32() : U32 =>
        (let ip1,let ip2,let ip3,let ip4) = ip
        (U32.from[U8](ip1)<<24)
        + (U32.from[U8](ip2)<<16)
        + (U32.from[U8](ip3)<<8)
        + U32.from[U8](ip4)

    fun box host_str() : String iso^ =>
        host.string()

    fun box port_str() : String iso^ =>
        port.string()

    fun box is_ipv4() : Bool =>
        (let ip1,let ip2,let ip3,let ip4) = ip
        (ip1 + ip2 + ip3 + ip4) == 0

    fun box string() : String iso^ =>
        (host + ":" + port.string()).string()