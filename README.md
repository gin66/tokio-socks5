# uservpn-socks5

This is work in progress project.
It shall be: A multi-server and multi-client vpn to internet showing up as socks5-proxy on client side

The tokio-socks5 project has been used as basis for the implementation.

[![Build Status](https://travis-ci.org/gin66/uservpn-socks5.svg?branch=mba)](https://travis-ci.org/gin66/uservpn-socks5)

## Motivation
There are already several vpn-solutions, which all do not fully meet my requirements. My set up is multiple servers and few clients to make use of this. The servers are located in different continents and as such the best server for accessing the internet depends on the URL.

Solutions as per my knowledge:
* openvpn: Only point-to-point and not always working well (blocked)
* tinc: Is distributed, but internet access depending on URL is not supported.
* vpncloud: Similar to tinc. Internet access is difficult.
* kcptun: Only point to point
* shadowsocks: Only point-to-point

The first four make use of a tun- or tap-device. Thus root is needed on client and server, which is IMHO a drawback.

## Requirements
* R01 Several clients connect to several servers
* R02 The servers are assumed to have good internet connection
* R03 List of static servers (IP/port)
* R04 Servers and their IPs can be extended dynamically
* R05 Server inform each other about client's IP
* R06 Servers and clients are uniquely numbered
* R07 Client decide server for internet access for one site
* R08 Client uses same server for selected site for whole session
* R09 Client uses socks protocol in order to avoid tcp-over-tcp problem
* R10 Server/Client keeps tcp connections alive
* R11 Client uses one cache per server
* R12 Out of band messages supported
* R13 Client requests messages to be sent/resent
* R14 Client-Server communication uses encryption
* R15 Encryption uses static shared key (no session authentication protocol)
* R16 Client-Server communication is pluggable for protocols
* R16.1 Protocol TCP
* R16.2 Protocol UCP
* R16.3 Protocol KCP
* R17 Client asks server for their connection time to a site
* R18 Client/server round trip is measured
* R19 Server informs client about client's IP/Port connections
* R20 Server communicates only, if minimum one client is connected
* R21 Each server keeps persistent tcp-connection to static servers
* R22 Each server maintains database of servers/clients
* R23 Each server keeps cache of client messages
* R24 Encryption of header with watermarking
* R25 Client acts as socks server for local/direct connections
* R26 Server-Client together implement socks5-proxy
* R27 Language should be rust (for performance reasons)
* R28 Portion of traffic from client to server will be always sent to other servers
* R29 Server intercommunication happens on new client connect
* R30 Server maintains one cache per client
* R31 Autoupdate of all Servers triggered by client informing about latest SW
* R32 SW distribution via github
* R33 If a server dies, all connections are dropped

## Usage - OUTDATED

First, run the server

```
$ cargo run
   ...
Listening for socks5 proxy connections on 127.0.0.1:8080
```

Then in a separate window you can test out the proxy:

```
$ export https_proxy=socks5h://localhost:8080
$ curl -v https://www.google.com
```

If you have an older version of libcurl which doesn't support the `socks5h` scheme,
you can try:

```
$ curl -v --socks5-hostname localhost:8080 https://www.google.com
```

The server is hardcoded to use Google's public DNS resolver (IPv4 address 8.8.8.8).
If you can't use external DNS services, change the address in the source and
rebuild the server.

# License

This project is licensed under either of

 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT)

at your option.

