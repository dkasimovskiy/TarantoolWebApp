local json = require('json')
local log = require('log')
local codes = require('http.codes')

function http_created(req) return http_response(req, 201) end
function http_no_content(req) return http_response(req, 204) end
function http_bad_request(req) return http_response(req, 400) end
function http_not_found(req) return http_response(req, 404) end
function http_conflict(req) return http_response(req, 409) end
function http_too_many_requests(req) return http_response(req, 429) end
function http_server_error(req) return http_response(req, 500) end

function http_response(req, http_status_code)
	if http_status_code == nil or codes[http_status_code] == nil then
		http_status_code = 500
	end

	local resp = req:render({text = http_status_code .. ' ' .. codes[http_status_code] .. "\n"})
	resp.status = http_status_code
	return resp
end

local function get_item(req, id, tuple)
	local resp = req:render({json = tuple['v']})
	resp.status = 200
	return resp
end

local function create_item(req)
	local data = req:json()

	if data == nil or data['key'] == nil or data['value'] == nil then
		return http_bad_request(req)
	end

	local status, error = pcall(function() box.space.kv:insert{tostring(data['key']), data['value']} end)
	if not status then
		log.warn('INSERT key %s failed: %s', data['key'], error)
		return http_conflict(req)
	end

	return http_created(req)
end

local function update_item(req, id, tuple)
	local data = req:json()
	if data == nil or data['value'] == nil then
		return http_bad_request(req)
	end

	local status, error = pcall(function() box.space.kv:replace{id, data['value']} end)
	if not status then
		log.warn('UPDATE key %s failed: %s', id, error)
		return http_server_error(req)
	end

	return http_no_content(req)
end

local function delete_item(req, id, tuple)
	local status, error = pcall(function() box.space.kv:delete{id} end)
	if not status then
		log.warn('DELETE key %s failed: %s', id, error)
		return http_server_error(req)
	end

	return http_no_content(req)
end

local function request_handler(req)
	if req.headers[RATE_LIMIT_HEADER] ~= nil then
		return http_too_many_requests(req)
	end

	if req.method ~= 'POST' then
		local id = req:stash('id')
		local tuple = box.space.kv:get{id}
		if tuple == nil then
			return http_not_found(req)
		end

		if req.method == 'GET' then
			return get_item(req, id, tuple)
		elseif req.method == 'PUT' then
			return update_item(req, id, tuple)
		elseif req.method == 'DELETE' then
			return delete_item(req, id, tuple)
		end
	else
		return create_item(req)
	end
end

return {
	get = function (self) return request_handler(self) end,
	create = function (self) return request_handler(self) end,
	update = function (self) return request_handler(self) end,
	delete = function (self) return request_handler(self) end
}