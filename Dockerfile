FROM tarantool/tarantool:2.8
EXPOSE 3301
EXPOSE 8080
COPY src/ /opt/tarantool
CMD ["tarantool", "/opt/tarantool/app.lua"]