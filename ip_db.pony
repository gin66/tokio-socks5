use "files"
use "logger"
use "regex"

class IpDB
    var db_from:Array[U32] = Array[U32](460589)
    var db_to  :Array[U32] = Array[U32](460589)
    var cn:Array[U16]      = Array[U16](460589)
    let _logger: Logger[String]

    new create(filename: FilePath val, logger: Logger[String]) =>
        _logger = logger
        match OpenFile(filename)
        | let file: File =>
            try
                let ip = "\"(\\d+)\\.(\\d+)\\.(\\d+)\\.(\\d+)\""
                let rex = Regex(ip + "," + ip + ",\"([A-Z][A-Z])\"")?
                try
                    for line in FileLines(file) do
                        logger(Fine) and logger.log(line)
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
                        logger(Fine) and logger.log(from_ip.string()+" "+to_ip.string()+" "+country.string())
                    end
                end
            end
        else
            logger(Info) and logger.log("Error opening file '" + filename.path + "'")
        end

    fun locate(addr: U32): U16 =>
        var i: USize = 0
        var j: USize = db_from.size()-1
        var k: USize = 0
        while i <= j do
            k = (i+j)>>1
            try
                if addr < db_from(k)? then
                    j = k-1
                elseif addr > db_from(k)? then
                    i = k+1
                else
                    return cn(k)?
                end
            else
               _logger(Error) and _logger.log("Error") 
            end
        end
        try
            _logger(Fine) and _logger.log(i.string()+"/"+j.string()+"/"+k.string())
            if (db_from(j)? <= addr) and (addr <= db_to(j)?) then
                cn(j)?
            else
                0
            end
        else
            0 
        end
