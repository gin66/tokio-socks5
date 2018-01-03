actor Chooser
    new create(network: Network) =>
        None

    be select_connection(dialer: Dialer,addr: InetAddrPort iso) =>
        dialer.connect_direct(consume addr)
        try
            let proxy_addr = recover val InetAddrPort.create_from_host_port("127.0.0.1:40005")? end
            let proxies    = recover iso [proxy_addr] end
            //dialer.connect_socks5_to(consume proxies)
        end
