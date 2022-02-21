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

box.once("bootstrap", function()
	local kv_storage = box.schema.space.create('kv', {if_not_exists = true})
	kv_storage:format({
		{name = 'k', type = 'string', is_nullable=false},
		{name = 'v', type = 'any', is_nullable=false}
	})
	kv_storage:create_index('primary', {unique = true, if_not_exists = true,
		parts = {{'k', 'string'}}
	})

	box.schema.user.create('kv_user', { password = 'secret', if_not_exists = true })
	box.schema.user.grant('kv_user', 'read,write,execute', 'space', 'kv')
end)

local log = require('log')
local pickle = require('pickle')

-- Configure HTTP server
local http_server = require('http.server')
local httpd = http_server.new('0.0.0.0', 8080, {
	log_requests = false,
	log_errors = true,
	header_timeout = 1
})


-- Confirure throttle service
local APP_RL_TOTAL = tonumber(os.getenv('APP_RATE_LIMIT_TOTAL'))
local APP_RL_TIME_FRAME_SEC = tonumber(os.getenv('APP_RATE_LIMIT_TIME_FRAME_SEC'))

if APP_RL_TOTAL ~= nil and APP_RL_TIME_FRAME_SEC ~= nil and APP_RL_TOTAL > 0 and APP_RL_TIME_FRAME_SEC > 0 then
	local clock = require('clock')

	RATE_LIMIT_HEADER = 'x-rate-limit'

	local prev_rate = APP_RL_TOTAL
	local curr_rate = 0
	local start_time = clock.time()

	local function sliding_window_rate_limit(r)
		local now = clock.time()
		if (now - start_time) > APP_RL_TIME_FRAME_SEC then
			start_time = now
			prev_rate = curr_rate
			curr_rate = 0
		end

		local slide_prct = (APP_RL_TIME_FRAME_SEC - (now - start_time)) / APP_RL_TIME_FRAME_SEC
		local estimated_count = (prev_rate * slide_prct) + curr_rate
		log.debug('slide: %s prev: %s current: %s estimated: %s', slide_prct, prev_rate, curr_rate, estimated_count)

		if estimated_count > APP_RL_TOTAL then
			r.headers[RATE_LIMIT_HEADER] = 1
			return
		end

		curr_rate = curr_rate + 1
	end

	httpd:hook('before_dispatch', function (h, req) sliding_window_rate_limit(req) end)
end


httpd:hook('after_dispatch', function (cx, resp)
	local s = pickle.pack('A', resp['body'] or '')
	log.info('"%s %s HTTP/%d.%d" %s %i', cx.method, cx.path, cx.proto[1], cx.proto[2], resp['status'], #s)
end)

httpd:route({method = 'GET', path = '/kv/:id'}, "kv#get")
httpd:route({method = 'POST', path = '/kv'}, "kv#create")
httpd:route({method = 'PUT', path = '/kv/:id'}, "kv#update")
httpd:route({method = 'DELETE', path = '/kv/:id'}, "kv#delete")
httpd:start()