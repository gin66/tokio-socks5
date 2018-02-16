// This module captures all relevant information from all areas.
//
use std::rc::Rc;
use std::str::FromStr;
use std::option::Option;
use std::net::{SocketAddr};
use ini;
use country::{country_hash,MAX_COUNTRY_HASH};

#[derive(Debug)]
pub struct Node {
    id: u8,
    name: String,
    probe: Option<String>,
    country_code: Option<usize>,
    pub socks5_listen_port: Option<SocketAddr>
}

#[derive(Debug)]
pub struct Database {
    pub nodes: Vec<Option<Node>>,
    pub proxy_to: Vec<Option<Vec<SocketAddr>>>,
    pub country_to_nodes: Vec<Option<Vec<u8>>>
}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        let mut db = Database {
            nodes: vec!(),   // Array of Nodes set to None
            proxy_to: vec!(),
            country_to_nodes: vec!()
        };
        for _i in 0..255 {
            db.nodes.push(None);
            db.proxy_to.push(None);
        };
        for _i in 1..MAX_COUNTRY_HASH {
            db.country_to_nodes.push(None);
        }
        Rc::new(db)
    }

    pub fn read_from_ini(&mut self, config: ini::Ini) -> Result<(),(&str)> {
        // Print parsed config file for debugging
        for (sec, prop) in config.iter() {
            println!("Section: {:?}", *sec);
            for (k, v) in prop.iter() {
                println!("   {}:{}", *k, *v);
            }
        }

        match config.section(Some("Nodes")) { 
            Some(section) =>  {
                for (k,v) in section.iter() { 
                    println!("NODE  {}:{}", *k, *v);
                    let nodename: &str = &v.to_string();
                    let id = k.to_string();
                    let id = u8::from_str(&id).unwrap();
                    match config.section(Some(nodename)) {
                        Some(ref node_section) => {
                            let mut new_node = Node {
                                id,
                                name: nodename.to_string(),
                                probe: None,
                                country_code: None,
                                socks5_listen_port: None
                            };
                            for (k,v) in node_section.iter() {
                                match k.as_ref() {
                                    "Probe" => {
                                        new_node.probe = Some(v.to_string());
                                    },
                                    "Socks5Address" => {
                                        match v.to_string().parse::<SocketAddr>() {
                                            Err(e) => return Err("Socks5Address is wrong"),
                                            Ok(sa) => new_node.socks5_listen_port = Some(sa)
                                        }
                                    },
                                    "Country" if v.len() == 2 => {
                                        let country = v.to_string().to_lowercase().into_bytes();
                                        let code = country_hash(&[country[0],country[1]]);
                                        if let Some(ch) = code {
                                            new_node.country_code = Some(ch);
                                            if None == self.country_to_nodes[ch] {
                                                self.country_to_nodes[ch] = Some(vec!())
                                            }
                                            if let Some(ref mut id_list) = self.country_to_nodes[ch] {
                                                id_list.push(id)
                                            }
                                        }
                                    },
                                    _ if k.contains("SocksProxy->") => {
                                        let to_id = k[12..].to_string();
                                        let to_id = u8::from_str(&to_id).unwrap();
                                        let mut sa_list: Vec<SocketAddr> = vec!();
                                        let split = v.split(",");
                                        for add in split {
                                            match add.parse::<SocketAddr>() {
                                                Err(e) => return Err("SocksProxy Address is wrong"),
                                                Ok(sa) => {
                                                    //println!("Node {} -> {:?}",to_id,&sa);
                                                    sa_list.push(sa)
                                                }
                                            }    
                                        }
                                        if sa_list.len() > 0 {
                                            self.proxy_to[to_id as usize] = Some(sa_list)
                                        }
                                    },
                                    _ => {
                                        println!("UNKNOWN NODESECTION  {}:{}", *k, *v);
                                    }
                                };
                            }
                            self.nodes[id as usize] = Some(new_node)
                        },
                        None => return Err("Cannot find node section")
                    }
                };
            },
            None => return Err("No [Nodes] section config-file")
        };
        Ok(())
    }
}