# xbs - Crystal implementation of the xBrowserSync API.
# See the API spec at https://api.xbrowsersync.org/

require "uri"
require "http"
require "json"
require "db"
require "sqlite3"
require "option_parser"
require "yaml"
require "logger"
require "uuid"

# Class for reading configuration information from xbs.yml.

class Config
  # Required settings
  getter port : Int32
  getter db : String

  # Optional settings
  getter sslport : (Int32|Nil)
  getter key : (String|Nil)
  getter cert : (String|Nil)
  getter log : (String|Nil)
  getter loglevel : (String|Nil)

  # Optional settings that get default values if not specified.
  getter version : String
  getter maxsyncsize : Int32
  getter status : Int32
  getter message : String

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

    # Provide defaults for version, maxsyncsize, status, and message if not specifed.
    # status: 1 = Online; 2 = Offline; 3 = Not accepting new syncs
    if yaml["version"]?
      @version =  yaml["version"].as_s
    else
      @version = "1.1.13"
    end
    if yaml["maxsyncsize"]?
      @maxsyncsize = yaml["maxsyncsize"].as_i
    else
      @maxsyncsize = 2 * 1024 * 2024
    end
    if yaml["status"]?
      @status = yaml["status"].as_i
      if status < 1 || status > 3
	puts "Invalid status #{status}.  Must be between 1 and 3"
	exit 1
      end
    else
      @status = 1
    end
    if yaml["message"]?
      @message = yaml["message"].as_s
    else
      @message = "Welcome to xbs, the Crystal implementation of the xBrowserSync API"
    end
  end
end

# Logger class that reads the log level and log filename from xbs.yml

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

# Class for handling accesses to the bookmarks Sqlite3 database.

class BookmarksDB
  def initialize(config : Config)
    # Set up the database connection.
    @config = config
    @dbname = config.db
    @db = uninitialized DB::Database	# This avoids compiler error
    @db = DB.open "sqlite3://#{@dbname}"
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

  # Create empty bookmarks record, return JSON response.
  def create_bookmarks : String
    uuid = UUID.random.hexstring
    bookmarks = ""
    t = Time.utc
    lastupdated = Time::Format::ISO_8601_DATE_TIME.format(t)
    MyLog.debug "insert into #{@table} values (#{uuid}, #{bookmarks}, #{@version}, #{lastupdated})"
    sql = "insert into #{@table} values (?, ?, ?, ?)"
    @db.exec sql, uuid, bookmarks, @version, lastupdated
    return {"id" => uuid, "lastUpdated" => lastupdated, "version" => @version}.to_json
  end

  # Get bookmarks for given ID, return JSON response.
  def get_bookmarks(id : String) : String
    url = nil
    if @db
      begin
	MyLog.debug "Attempting to get bookmarks for id #{id} from #{@dbname}:#{@table}"
	sql = "select bookmarks,lastupdated,version from #{@table} where uuid = ?"
	MyLog.debug "Executing #{sql}, ? = #{id}"
	bookmarks, lastupdated, version = @db.query_one(sql, id, as: {String, String, String})
	if bookmarks
	  MyLog.debug "Got bookmarks for #{id} from sqlite3 query #{sql}"
	  return {"bookmarks" => bookmarks, "lastUpdated" => lastupdated,
	          "version" => version}.to_json
	else
	  MyLog.debug "Unable to find #{id} in sqlite3"
	  return "401:Sync does not exist"
	end
      rescue ex
	MyLog.error "sqlite3 exception: #{ex.message}"
	return "401:Sync does not exist"
      end
    end
    return ""
  end

  # Get last updated timestamp for given ID, return JSON response.
  def get_lastupdated(id : String, as_json = true) : String
    url = nil
    if @db
      begin
	MyLog.debug "Attempting to get lastupdated for id #{id} from #{@dbname}:#{@table}"
	sql = "select lastupdated from #{@table} where uuid = ?"
	MyLog.debug "Executing #{sql}, ? = #{id}"
	lastupdated = @db.query_one(sql, id, as: String)
	if lastupdated
	  MyLog.debug "Got lastupdated #{lastupdated} for #{id} from sqlite3 query #{sql}"
	  if as_json
	    return {"lastUpdated" => lastupdated}.to_json
	  else
	    return lastupdated;
	  end
	else
	  MyLog.debug "Unable to find #{id} in sqlite3"
	  return "401:Sync does not exist"
	end
      rescue ex
	MyLog.error "sqlite3 exception: #{ex.message}"
	return "401:Sync does not exist"
      end
    end
    return ""
  end

  # Get sync version given ID, return JSON response.
  def get_syncversion(id : String) : String
    url = nil
    if @db
      begin
	MyLog.debug "Attempting to get sync version for id #{id} from #{@dbname}:#{@table}"
	sql = "select version from #{@table} where uuid = ?"
	MyLog.debug "Executing #{sql}, ? = #{id}"
	version = @db.query_one(sql, id, as: String)
	if version
	  MyLog.debug "Got version #{version} for #{id} from sqlite3 query #{sql}"
	  return {"version" => version}.to_json
	else
	  MyLog.debug "Unable to find #{id} in sqlite3"
	  return "401:Sync does not exist"
	end
      rescue ex
	MyLog.error "sqlite3 exception: #{ex.message}"
	return "401:Sync does not exist"
      end
    end
    return ""
  end

  # Update bookmarks for ID, return JSON response.
  def update_bookmarks(id : String, content_type : String, body : String)
    if @db
      begin
	MyLog.debug "Attempting to update bookmarks for id #{id} in #{@dbname}:#{@table}, body '#{body[0,10]}...'"
	values = Hash(String, String).from_json(body)
	bookmarks = values["bookmarks"]

	# Check that the current version matches the expected one.
	# If they don't match, we must be in a race condition, where
	# another client updated the bookmarks after this client
	# checked the lastUpdated value.  So don't write to the database,
	# but report a confict error instead.  In theory, this should
	# cause this client to retrieve the bookmarks.
	check_lastupdated = values["lastUpdated"]
	lastupdated = get_lastupdated(id, as_json: false)
	if lastupdated != check_lastupdated
	  return "409:A sync conflict was detected"
	end

	t = Time.utc
	lastupdated = Time::Format::ISO_8601_DATE_TIME.format(t)
	sql = "update  #{@table} set bookmarks = ?, lastupdated = ? where uuid = ?"
	MyLog.debug "Executing #{sql}, bookmarks = #{bookmarks[0,10]}..., lastupdated = #{lastupdated}, uuid = #{id}"
	@db.exec sql, bookmarks, lastupdated, id
	return {"lastUpdated" => lastupdated}.to_json
      rescue ex
	MyLog.error "sqlite3 exception: #{ex.message}"
        return "401:Sync does not exist"
      end
    end
    return ""
  end

end

# Simple HTTP server for the xBrowserSync API.

class Server
  def initialize(config : Config)
    @config = config
    @db = BookmarksDB.new(config)
    @server = uninitialized HTTP::Server
  end

  def process_request(context : HTTP::Server::Context)
    request = context.request
    path = request.path
    method = request.method
    MyLog.debug "process_request: got path #{path}, method #{method}"

    if @config.status == 2
      context.response.respond_with_status(503, "The service is currently is offline")
      return
    end
    json = ""
    text = ""

    # Use regular expressions to parse the recognized routes for the API.
    # Most of these routes take an ID parameter, which is the 32-character
    # UUID for a bookmark record.
    if path =~ /bookmarks\/([[:xdigit:]]+)\/version/
      id = $1
      json = @db.get_syncversion(id)
    elsif path =~ /bookmarks\/([[:xdigit:]]+)\/lastUpdated/
      # Get the timestamp for the specified bookmark data.
      id = $1
      json = @db.get_lastupdated(id)
    elsif path =~ /bookmarks\/([[:xdigit:]]+)/
      # GET means get the specified bookmark data.
      # PUT means update the bookmark data.
      id = $1
      if method == "PUT"
	body = request.body
	if body.nil?
	  bodystr = ""
	else
	  bodystr = body.gets_to_end
	end
	content_type = request.headers["Content-Type"]
	bodysize = bodystr.size
	maxsize = @config.maxsyncsize
	if bodysize > maxsize
	  json = "413:Sync data limit exceeded"
	else
	  json = @db.update_bookmarks(id, content_type, bodystr)
	end
      elsif method == "GET"
	json = @db.get_bookmarks(id)
      else
	json = "501:unknown method for bookmarks/ID"
      end
    elsif path == "/bookmarks"
      # Create a new bookmark record.
      if method == "POST"
	if @config.status == 3
	  json = "405:The service is not accepting new syncs"
	else
	  json = @db.create_bookmarks
	end
      else
	MyLog.error "/bookmarks not called with POST"
      end
    elsif path == "/info"
      # Get information about this server.
      json = {"maxSyncSize" => @config.maxsyncsize,
	      "message" => @config.message,
	      "status" => @config.status,
	      "version" => @config.version}.to_json
    elsif path == "/"
      # Display a welcome message if the user mistakenly tries
      # to access the root URL.
      text = @config.message
    else
      text = "Unrecognized request"
    end

    # If there is a JSON response, send that.  As a hack, the json string
    # can also encode an HTTP error response.
    if json.size > 0
      if json =~ /^(\d+):(.+)$/
	# Handle special case of NNN:message, where NNN is an HTTP status code,
	# and message is the message to send back.
	status = $1.to_i
	message = $2
	context.response.respond_with_status(status, message)
      else
	context.response.content_type = "application/json"
        context.response.print json
      end
    # If there is a plain text response, send that.
    elsif text.size > 0
      context.response.content_type = "text/plain"
      context.response.print text
    end
  end

  def start
    @server = HTTP::Server.new do |context|
      process_request(context)
    end

    if @server
      address = @server.bind_tcp "0.0.0.0", @config.port
      puts "Listening on http://#{address}"

      # If SSL is specified, set that up.  If you have Apache
      # available, it's probably better to NOT let xbs handle
      # SSL, but let Apache handle it and put xbs behind a
      # reverse proxy.
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
