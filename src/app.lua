box.cfg {
	listen = '0.0.0.0:3301';
	io_collect_interval = nil;
	readahead = 16320;
	memtx_memory = 128 * 1024 * 1024; -- 128Mb
	memtx_min_tuple_size = 16;
	memtx_max_tuple_size = 128 * 1024 * 1024; -- 128Mb
	vinyl_memory = 128 * 1024 * 1024; -- 128Mb
	vinyl_cache = 128 * 1024 * 1024; -- 128Mb
	vinyl_max_tuple_size = 128 * 1024 * 1024; -- 128Mb
	vinyl_write_threads = 2;
	wal_mode = "write";
	wal_max_size = 256 * 1024 * 1024;
	checkpoint_interval = 60 * 60; -- one hour
	checkpoint_count = 6;
	force_recovery = true;
	log_level = 5;
	log_nonblock = false;
	too_long_threshold = 0.5;
	read_only   = false
}

local function bootstrap()
	local space = box.schema.space.create('kv', {if_not_exists = true})
	space:format({
		{name = 'k', type = 'string', is_nullable=false},
		{name = 'v', type = 'string', is_nullable=false}
	})
	space:create_index('primary', {
		unique = true,
		if_not_exists = true,
		parts = {{'k', 'string'}}
	})

	box.schema.user.create('kv', { password = 'secret' })
	box.schema.user.grant('kv', 'read,write,execute', 'space', 'kv')

	box.schema.user.create('repl', { password = 'replication' })
	box.schema.user.grant('repl', 'replication')
end

-- for first run create a space and add set up grants
box.once('replica', bootstrap)

-- enabling console access
console = require('console')
console.listen('127.0.0.1:3302')

local http_server = require('http.server')
local httpd = http_server.new('0.0.0.0', 8080, {
	log_requests = true,
	log_errors = true,
	header_timeout = 1
})


httpd:route({method = 'GET', path = '/kv/:id'}, "kv#get")
httpd:route({method = 'POST', path = '/kv'}, "kv#create")
httpd:route({method = 'PUT', path = '/kv/:id'}, "kv#update")
httpd:route({method = 'DELETE', path = '/kv/:id'}, "kv#delete")

httpd:start()