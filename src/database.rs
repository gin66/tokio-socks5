// This module captures all relevant information from all areas.
//
use std::rc::Rc;
use ini;

pub struct Database {

}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        Rc::new(Database {

        })
    }

    pub fn read_from_ini(&mut self, config: ini::Ini, node_id: &str) {
        for (sec, prop) in config.iter() {
            println!("Section: {:?}", *sec);
            for (k, v) in prop.iter() {
                println!("   {}:{}", *k, *v);
            }
        }

        let nodename = match config.get_from(Some("Nodes"), node_id) {
            Some(name) => name,
            None => {
                println!("Node {} is not defined in config-file",node_id);
                return
            }
        };
        println!("This node is {} with name {}",node_id,nodename);

        let nodeconfig = match config.section(Some(nodename)) { 
            Some(section) => section,
            None => {
                println!("No section for node {} in config-file",nodename);
                return
            }
        };
        println!("{:?}",nodeconfig);

    }
}