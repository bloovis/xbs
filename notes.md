# UUID

```
require "uuid"
u = UUID.random
u.hexstring
```

# xBrowserSync API

https://api.xbrowsersync.org/

## Bookmarks

**Create bookmarks**

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

## Get bookmarks

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

## Update bookmarks

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

## Get last updated

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

## Get sync version

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

## Service information

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

