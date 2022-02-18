local json = require('json')
local codes = require('http.codes')
local log = require('log')

function http_created() return http_response(201) end
function http_no_content() return http_response(204) end
function http_bad_request() return http_response(400) end
function http_not_found() return http_response(404) end
function http_conflict() return http_response(409) end

function http_response(http_status_code)
	if http_status_code == nil or codes[http_status_code] == nil then 
		http_status_code = 500
	end

	return {status = http_status_code, body = http_status_code .. ' ' .. codes[http_status_code] .. "\n" }
end

local function get_item(r)
	local id = r:stash('id')
	if id == nil then
		return http_not_found()
	end

	local tuple = box.space.kv:get{id};
	if tuple == nil then
		return http_not_found()
	end

	return {status = 200, body = tuple['v']}
end

local function create_item(r)
	local data = r:json()

	if data == nil or data['key'] == nil or data['value'] == nil then
		return http_bad_request()
	end
	log.info('ITEM key:%s value:%s', data['key'], data['value'])

	local status, error = pcall(function() box.space.kv:insert{data['key'], json.encode(data['value'])} end)
	if status == false then
		log.info('INSERT DUP: %s %s', status, error)
		return http_conflict()
	end

	return http_created()
end


local function update_item(r)
	local id = r:stash('id')
	if id == nil then
		return http_not_found()
	end

	local data = r:json()
	if data == nil or data['value'] == nil then
		return http_bad_request()
	end

	local tuple = box.space.kv:get{id};
	if tuple == nil then
		return http_not_found()
	end
	
	box.space.kv:replace{id, json.encode(data['value'])};
	return http_no_content()
end

local function delete_item(r)
	local id = r:stash('id')
	if id == nil then
		return http_not_found()
	end

	local tuple = box.space.kv:get{id};
	if tuple == nil then
		return http_not_found()
	end
	
	box.space.kv:delete{id};
	return http_no_content()
end

return {
	get = function(self) return get_item(self) end,
	create = function(self) return create_item(self) end,
	update = function(self) return update_item(self) end,
	delete = function(self) return delete_item(self) end
}