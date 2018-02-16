// This module captures all relevant information from all areas.
//
use std::rc::Rc;
use std::str::FromStr;
use std::option::Option;
use ini;

pub struct Node {
    id: u8,
    name: String
}

pub struct Database {
    nodes: Vec<Option<Node>>
}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        let mut db = Database {
            nodes: vec!()   // Array of Nodes set to None
        };
        while db.nodes.len() < 256 {
            db.nodes.push(None)
        }
        Rc::new(db)
    }

    pub fn read_from_ini(&mut self, config: ini::Ini, node_id: &str) -> Result<(),(&str)> {
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
                    match config.section(Some(nodename)) {
                        Some(ref node_section) => {
                            println!("{:?}",node_section);
                            let id = k.to_string();
                            let id = u8::from_str(&id).unwrap();
                            let new_node = Node {
                                id,
                                name: nodename.to_string()
                            };
                            self.nodes[id as usize] = Some(new_node)
                        },
                        None => return Err("Cannot find node section")
                    }
                };
            },
            None => return Err("No [Nodes] section config-file")
        };

        let nodename = match config.get_from(Some("Nodes"), node_id) {
            Some(name) => name,
            None => return Err("Node is not defined in config-file")
        };
        println!("This node is {} with name {}",node_id,nodename);

        let nodeconfig = match config.section(Some(nodename)) { 
            Some(section) => section,
            None => return Err("No section for node {} in config-file")
        };
        println!("{:?}",nodeconfig);

        Ok(())
    }
}