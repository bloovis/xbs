# Xbs

Xbs is a server that implements the [xBrowserSync](https://www.xbrowsersync.org/)
[API](https://api.xbrowsersync.org/).  I looked at the [official source code](https://github.com/xbrowsersync/api)
for the API server, as well as a couple of alternatives written in Go,
[xbsapi](https://github.com/mrusme/xbsapi) and [xSyn](https://github.com/ishani/xsyn).
But they seemed too bulky and intimidating for self-hosting.
So I decided to write my own server in [Crystal](https://crystal-lang.org/), a Ruby-like compiled
language that has an excellent [HTTP library](https://crystal-lang.org/api/1.10.1/HTTP.html)
for writing tiny API servers.

## Prerequisites

Xbs requires C libraries for yaml and libsqlite3.  These can be installed on Debian
or Ubuntu using:

    sudo apt install libyaml-dev
    sudo apt install libsqlite3-dev

## Build

To build Xbs, use this:

    shards install
    crystal build src/xbs.cr

This will create a binary `xbs` in the current directory.  This executable
file and the configuration file (see the next section) are all that
you need for an xbs installation.

## Configuration

Xbs keeps its configuration information in a YAML file.  To create
an initial configuration, copy the file `xbs.yml.sample` to `xbs.yml` and edit as needed.
The configuration file contains these required fields:

* `db` - the pathname of the sqlite3 database to be used as a cache.  If the
  database does not exist, Xbs will attempt to create it.
* `port` - the number of the port to be used by the Xbs server.  The recommended
  value is 8090, to avoid conflict with Coce, which uses 8080.

The configuration file contains these optional fields:

* `sslport` - the number of the port to by used by the Xbs server for SSL (https) access.
This option is unnecessary if you are running Xbs behind an Apache reverse proxy
and Apache has been configured for SSL.  If you do set this option, you must
also set `key` and `cert`.
* `key` - the pathname of the file containing the SSL key.  For example,
if you obtained your key from Let's Encrypt, the pathname
might be something like `/etc/letsencrypt/live/www.example.com/privkey.pem`.
* `cert` - the pathname of the file containing the SSL certificate.  For example,
if you obtained your certificate from Let's Encrypt, the pathname
might be something like `/etc/letsencrypt/live/www.example.com/fullchain.pem`.
* `log` - the pathname of the log file.  Xbs will create the file if it does not
  exist; otherwise, it will append log messages to the end of the file.  If this field
  is not present, Xbs will send log messages to stdout.
* `loglevel` - the logging level, corresponding to the values of `Logger::Severity `:
    - debug
    - error
    - fatal
    - info
    - unknown
    - warn
* `version` - the version of the xBrowserSync API supported by Xbs.  If this field
  is not present, 1.1.13 will be used.
* `maxsyncsize` - the maximum sync size (in bytes) allowed by Xbs.  If this field
  is not present, 2MB will be used
* `status` - the current service status code: 1 = Online, 2 = Offline, 3 = Not accepting new syncs.
  If this field is not present, 1 will be used.
* `message` - the message to be shown to users of the xBrowserSync clients.  If this field
  is not present, "Welcome to xbs, the Crystal implementation of the xBrowserSync API" will
  be used.

## Running

To run Xbs as a server, use this:

    ./xbs [config-option] server

The server will run until terminated by a Control-C or other signal.

Xbs supports a single option: `--config=FILENAME`, which you can use
to specify to the path to the configuration YAML file.  The default
value is `./xbs.yml`.

## System Service

It is more convenient to start the Xbs server as a system service than to run it
from the command line.  To do this, follow these steps:

* Copy the file `xbs.service.sample` to `/etc/systemd/system/xbs.service`
  and edit it as necessary.  The values most likely to need editing are `WorkingDirectory`
  and `ExecStart`.
* Run `systemctl daemon-reload` to tell systemd about the new Xbs service
* Run `systemctl enable xbs` to enable the Xbs service
* Run `systemctl start xbs` to start the Xbs service
* Run `systemctl status xbs` to verify that the Xbs service is running

## Apache Reverse Proxy

It is probably a good idea to run Xbs behind an Apache reverse proxy.  That
way, Apache handle SSL (and rate limiting, if necessary), freeing Xbs
from having to deal with these complications.  To implement the reverse
proxy, you must first enable the Apache2 proxy modules:

    a2enmod proxy_http

Then add the following line to the VirtualHost section in the appropriate config file
in `/etc/apache2/sites-enabled/`.  On my system, using Let's Encrypt,
this file is `000-default-le-ssl.conf`.

    ProxyPass /xbs/ http://localhost:8090/ upgrade=websocket

## Testing

Xbs has been tested with the xBackupSync extension for Chrome.  You can test
it outside of a browser extension using the `curl` utility.  Run
Xbs in one terminal session, as shown above, and in another terminal
session, use the following commands to test the various API endpoints.
Most of the commands will return a JSON response.

### Create bookmarks

```
curl -X PUT 'http://localhost:8090/bookmarks'
```

This will return a JSON response containing the new ID (a randomly generated
32-character UUID) to be used in subsequent tests.  In the following
commands, replace "ID" with this ID.

### Get bookmarks

```
curl 'http://localhost:8090/bookmarks/ID'
```

### Get lastUpdated

curl 'http://localhost:8090/bookmarks/ID/lastUpdated'

## Get sync version

```
curl 'http://localhost:8090/bookmarks/ID/version'
```

### Update bookmarks

Note: the following command is shown on multiple lines for clarity,
but it should be typed on one line.
```
curl -X PUT -H "Content-Type: application/json" 
  -d '{"bookmarks":"bookmark data","lastUpdated":"2023-11-03T121:32:59Z"}'
  'http://localhost:8090/bookmarks/ID'
```

### Get service information

```
curl 'http://localhost:8090/info'
```

## xBrowserSync API

The official API specification is [here](https://api.xbrowsersync.org/).  For completeness,
the following is a copy of the specification as of version 1.1.13.


### Create bookmarks

`Post /bookmarks`

Creates a new (empty) bookmark sync and returns the corresponding ID.

*Post body example:*

```
{
    "version":"1.0.0"
}
```

**version:** Version number of the xBrowserSync client used to create the sync.

*Response example:*

```
{
    "id":"52758cb942814faa9ab255208025ae59",
    "lastUpdated":"2016-07-06T12:43:16.866Z",
    "version":"1.0.0"
}
```

* **id:** 32 character alphanumeric sync ID.
* **lastUpdated:** Last updated timestamp for created bookmarks.
* **version:** Version number of the xBrowserSync client used to create the sync.

### Get bookmarks

`Get /bookmarks/{id}`

Retrieves the bookmark sync corresponding to the provided sync ID.

*Query params:*

**id:** 32 character alphanumeric sync ID.

*Response example:*

```
{
    "bookmarks":"DWCx6wR9ggPqPRrhU4O4oLN5P09oULX4Xt+ckxswtFNds...",
    "lastUpdated":"2016-07-06T12:43:16.866Z",
    "version":"1.0.0"
}
```

* **bookmarks:** Encrypted bookmark data salted using secret value.
* **lastUpdated:** Last updated timestamp for retrieved bookmarks.
* **version:** Version number of the xBrowserSync client used to create the sync.

### Update bookmarks

`Put /bookmarks/{id}`

Updates the bookmark sync data corresponding to the provided sync ID with the provided encrypted bookmarks data.

*Query params:*

**id:** 32 character alphanumeric sync ID.

*Post body example:*
``
{
    "bookmarks":"DWCx6wR9ggPqPRrhU4O4oLN5P09oULX4Xt+ckxswtFNds...",
    "lastUpdated":"2016-07-06T12:43:16.866Z",
}
``

* **bookmarks:** Encrypted bookmark data salted using secret value.
* **lastUpdated:** Last updated timestamp to check against existing bookmarks.

*Response example:*

```
{
    "lastUpdated":"2016-07-06T12:43:16.866Z"
}
```

**lastUpdated:* Last updated timestamp for updated bookmarks.

### Get last updated

`Get /bookmarks/{id}/lastUpdated`

Retrieves the bookmark sync last updated timestamp corresponding to the provided sync ID.

*Query params:*

**id:** 32 character alphanumeric sync ID.

```
Response example:

{
    "lastUpdated":"2016-07-06T12:43:16.866Z"
}
```

**lastUpdated:** Last updated timestamp for corresponding bookmarks.

### Get sync version

`Get /bookmarks/{id}/version`

Retrieves the bookmark sync version number of the xBrowserSync client used to create the bookmarks sync corresponding to the provided sync ID.

*Query params:*

**id:** 32 character alphanumeric sync ID.

*Response example:*

```
{
    "version":"1.0.0"
}
```

**version:** Version number of the xBrowserSync client used to create the sync.

### Service information

Get service information

`Get /info`

Retrieves information describing the xBrowserSync service.

*Response example:*

```
{
    "maxSyncSize":204800,
    "message":"",
    "status":1,
    "version":"1.0.0"
}
```

* **status:** Current service status code. 1 = Online; 2 = Offline; 3 = Not accepting new syncs.
* **message:** Service information message.
* **version:** API version service is using.
* **maxSyncSize:** Maximum sync size (in bytes) allowed by the service.

