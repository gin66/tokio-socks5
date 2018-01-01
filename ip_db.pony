use "files"
use "logger"
use "regex"

actor IpDB
    var db_from:Array[U32] = Array[U32](460589)
    var db_to  :Array[U32] = Array[U32](460589)
    var cn:Array[U16]      = Array[U16](460589)
    let _logger: Logger[String]
    let _iterator: Iterator[String val] ref
    var _rex: (Regex | None)

    new create(filename: FilePath val, logger: Logger[String]) =>
        _logger = logger

        _rex = None
        try 
            let ip = "\"(\\d+)\\.(\\d+)\\.(\\d+)\\.(\\d+)\""
            _rex = Regex(ip + "," + ip + ",\"([A-Z][A-Z])\"")?
        end
        match OpenFile(filename)
        | let file: File =>
            _logger(Info) and _logger.log("Start load of Geo IP database")
            _iterator = FileLines(file)
            load_next()
        else
            _logger(Info) and _logger.log("Error opening file '" + filename.path + "'")
            _iterator = Array[String].values()
        end

    be load_next() =>
        try
            match _rex
            | let rex: Regex =>
                let line = _iterator.next()?
                _logger(Fine) and _logger.log(line)
                let matched = rex(line)?
                var from_ip: U32 = 0
                var to_ip:   U32 = 0
                var country: U16 = 0

                from_ip = matched(1)?.u32()?
                from_ip = (from_ip << 8) + matched(2)?.u32()?
                from_ip = (from_ip << 8) + matched(3)?.u32()?
                from_ip = (from_ip << 8) + matched(4)?.u32()?
                to_ip = matched(5)?.u32()?
                to_ip = (to_ip << 8) + matched(6)?.u32()?
                to_ip = (to_ip << 8) + matched(7)?.u32()?
                to_ip = (to_ip << 8) + matched(8)?.u32()?
                country = U16.from[U8](matched(9)?(0)?)
                country = U16.from[U8](matched(9)?(1)?) + (country<<8)
                db_from.push(from_ip)
                db_to.push(to_ip)
                cn.push(country)
                _logger(Fine) and _logger.log(from_ip.string()+" "+to_ip.string()+" "+country.string())
                load_next()
            end
        else
            _logger(Info) and _logger.log("Geo IP database load completed")
            locate(1047275918)
        end


    be locate(addr: U32) =>
        let country = _locate(addr)
        var ans = String(2)
        ans.push(U8.from[U16](country >> 8))
        ans.push(U8.from[U16](country % 256))
        _logger(Info) and _logger.log(ans.string())

    fun ref _locate(addr: U32): U16 =>
        // Offset 1, because j could be -1 otherwise
        var i: USize = 1
        var j: USize = db_from.size()
        var k: USize = 1
        while i <= j do
            k = (i+j)>>1
            try
                if addr < db_from(k-1)? then
                    j = k-1
                elseif addr > db_from(k-1)? then
                    i = k+1
                else
                    return cn(k-1)?
                end
            else
               _logger(Error) and _logger.log("Error"+k.string()+""+i.string()
                        +"/"+j.string()) 
                return 0
            end
        end
        try
            _logger(Fine) and _logger.log(i.string()+"/"+j.string()+"/"+k.string())
            if (j > 1) and (db_from(j-1)? <= addr) and (addr <= db_to(j-1)?) then
                cn(j-1)?
            else
                0
            end
        else
            0 
        end
