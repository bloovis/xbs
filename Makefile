xbs : src/xbs.cr shard.lock
	crystal build src/xbs.cr

shard.lock : shard.yml
	shards install
