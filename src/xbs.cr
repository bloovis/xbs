require "uri"
require "http"
require "json"
require "db"
require "sqlite3"
require "option_parser"
require "yaml"
require "logger"
require "uuid"

class Config
  getter port : Int32
  getter db : String
  getter sslport : (Int32|Nil)
  getter key : (String|Nil)
  getter cert : (String|Nil)
  getter log : (String|Nil)
  getter loglevel : (String|Nil)

  def initialize(config_file : String)
    yaml = File.open(config_file) {|file| YAML.parse(file) }

    # db, and port are required.
    @db = yaml["db"].as_s
    @port = yaml["port"].as_i

    # sslport, key, and cert are optional.
    if yaml["sslport"]?
      @sslport = yaml["sslport"].as_i
      @key = yaml["key"].as_s
      @cert = yaml["cert"].as_s
    end

    # log and loglevel are optional.
    if yaml["log"]?
      @log = yaml["log"].as_s
    end
    if yaml["loglevel"]?
      @loglevel = yaml["loglevel"].as_s
    end
  end
end

module MyLog
  extend self

  @@log = uninitialized Logger

  def configure(config : Config)
    levels = {
      "DEBUG"   => Logger::DEBUG,
      "ERROR"   => Logger::ERROR,
      "FATAL"   => Logger::FATAL,
      "INFO"    => Logger::INFO,
      "UNKNOWN" => Logger::UNKNOWN,
      "WARN"    => Logger::WARN
    }

    filename = config.log || ""
    loglevel = config.loglevel || "DEBUG"
    if filename.size > 0
      file = File.open(filename, "a+")
      @@log = Logger.new(file)
    else
      @@log = Logger.new(STDOUT)
    end
    @@log.level = levels[loglevel.upcase]
  end

  delegate debug, to: @@log
  delegate error, to: @@log
  delegate fatal, to: @@log
  delegate info, to: @@log
  delegate unknown, to: @@log
  delegate warn, to: @@log

  def close
    @log.close
  end
end

class BookmarksDB
  def initialize(dbname : String)	# sqlite3 database filename
    # Set up the database connection.
    @db = uninitialized DB::Database	# This avoids compiler error
    @db = DB.open "sqlite3://#{dbname}"
    @dbname = dbname
    @table = "bookmarks"
    @version = "1.1.13"

    # Create the table if it does not already exist.
    sql = <<-SQL
      CREATE TABLE IF NOT EXISTS #{@table} (
        uuid text primary key not null,
        bookmarks text not null,
        version text not null,
        lastupdated text not null)
    SQL
    MyLog.debug "Executing #{sql}"
    @db.exec sql
  end

  def finalize
    if @db
      @db.close
    end
  end

  # Create empty bookmarks record
  def create_bookmarks
    id = UUID.random.hexstring
    bookmarks = ""
    t = Time.utc
    lastupdated = Time::Format::ISO_8601_DATE_TIME.format(t)
    MyLog.debug "insert into #{@table} values (#{id}, #{bookmarks}, #{@version}, #{lastupdated})"
    sql = "insert into #{@table} values (?, ?, ?, ?)"
    @db.exec sql, id, bookmarks, @version, lastupdated
  end

  # Get bookmarks for given ID.
  def get_bookmarks(id : String)
    url = nil
    if @db
      begin
	MyLog.debug "Attempting to get bookmarks for id #{id} from #{@dbname}:#{@table}"
	sql = "select bookmarks from #{@table} where id = ? limit 1"
	MyLog.debug "Executing #{sql}, ? = #{id}"
	bookmarks = @db.query_one?(sql, id, as: String)
	if bookmarks
	  MyLog.debug "Got bookmarks for #{id} from sqlite3 query #{sql}"
	else
	  MyLog.debug "Unable to find #{id} in sqlite3"
	end
      rescue ex
	MyLog.error "sqlite3 exception: #{ex.message}"
      end
    end
    return bookmarks
  end
end

class Server
  def initialize(config : Config)
    @config = config
    @db = BookmarksDB.new(config.db)
    @server = uninitialized HTTP::Server
  end

  def process_request(context : HTTP::Server::Context)
    path = context.request.path
    method = context.request.method
    MyLog.debug "process_request: got path #{path}, method #{method}"

    puts "Got request method #{method}, path #{path}"
    if path =~ /bookmarks\/([[:xdigit:]]+)\/version/
      id = $1
      puts "Get sync version for ID #{id}"
    elsif path =~ /bookmarks\/([[:xdigit:]]+)\/lastUpdated/
      id = $1
      puts "Get last updated timestamp for ID #{id}"
    elsif path =~ /bookmarks\/([[:xdigit:]]+)/
      id = $1
      if method == "PUT"
        puts "update bookmarks for #{id}"
      elsif method == "GET"
        puts "get bookmarks for #{id}"
      else
	puts "unknown method for bookmarks/ID"
      end
    elsif path == "/bookmarks"
      if method == "PUT"
	puts "create new bookmarks ID"
	@db.create_bookmarks
      else
	puts "/bookmarks not called with PUT!"
      end
    elsif path == "/info"
      puts "Get service information"
    elsif path == "/"
      context.response.content_type = "text/plain"
      context.response.print "Welcome to xbs, the Crystal implementation of the xBrowserSync API"
    else
      context.response.content_type = "text/plain"
      context.response.print "Unrecognized request"
    end
  end

  def start
    @server = HTTP::Server.new do |context|
      process_request(context)
    end

    if @server
      address = @server.bind_tcp "0.0.0.0", @config.port
      puts "Listening on http://#{address}"
      if @config.sslport
	ssl_context = OpenSSL::SSL::Context::Server.new
	ssl_context.certificate_chain = @config.cert || ""
	ssl_context.private_key = @config.key || ""
	@server.bind_tls "0.0.0.0", @config.sslport || 0, ssl_context
	puts "Listening on SSL port #{@config.sslport}"
      end
      @server.listen
    end
  end

  def stop
    MyLog.debug "Server::stop"
    if @server
      @server.close
    end
  end
end

def doit
  banner = <<-BANNER
xbs [options]
BANNER

  config_file = "./xbs.yml"

  OptionParser.parse do |parser|
    parser.banner = banner
    parser.on("-c FILENAME", "--config=FILENAME",
              "Specifies the config filename") { |name| config_file = name }
  end

  # Read config file.
  puts "Using config file " + config_file
  config = Config.new(config_file);

  # Set up logging.
  MyLog.configure(config)

  # Start the server.
  server = Server.new(config)
  server.start
  server.stop
end

doit
