-module(recall).
-export([start/0]).
-export([start_listener/1, accept_clients/2, register_client/2, loop/1, client_loop/2]).
-compile(export_all).


-define(DEFAULT_PORT, 9900).

-record(session, {socket, accepter, clients}).
-record(client, {socket, name, pid}).


start() -> 
    spawn(?MODULE, start_listener, [?DEFAULT_PORT]).

start_listener(Port) ->
    {ok, Socket} = gen_tcp:listen(Port, [{packet, 0}, {active, false}]),
    Accepter = spawn_link(?MODULE, accept_clients, [Socket, self()]),
	io:fwrite("--> Recall Server Started on port ~B...~n", [Port]),
    loop(#session{socket = Socket, accepter = Accepter, clients = []}).


loop(Session = #session{accepter = A, clients = Cs}) ->
    receive
        {'new client', Client} ->
            erlang:monitor(process, Client#client.pid),
            Cs1 = [Client|Cs],
            io:fwrite("--> new connection from ~s\r\n", [Client#client.name]),
            loop(Session#session{clients = Cs1});

        {'DOWN', _, process, Pid, _Info} ->
            case lists:keysearch(Pid, #client.pid, Cs) of
                false -> loop(Session);
                {value, Client} -> 
                    self() ! {'lost client', Client},
                    loop(Session)
            end;

        {'lost client', Client} ->
            io:fwrite("--> lost connection from ~s\r\n", [Client#client.name]),
            gen_tcp:close(Client#client.socket),
            loop(Session#session{clients = lists:delete(Client, Cs)});

        refresh ->
            io:fwrite("--> Refreshing Recall server...", []),
            A ! refresh,
            lists:foreach(fun (#client{pid=CP}) -> CP ! refresh end, Cs),
            ?MODULE:loop(Session);

        quit ->
            io:fwrite("--> Exiting Recall server...", []),
            A ! quit,
            lists:foreach(fun (#client{pid=CP}) -> CP ! quit end, Cs)
    end.


accept_clients(Socket, Server) ->
    case gen_tcp:accept(Socket) of
        {ok, Client} -> spawn(?MODULE, register_client, [Client, Server]);
        {error, Reason} -> io:fwrite("--> Error connecting to client: ~s~n", [Reason]) 
    end,
    receive
        refresh -> ?MODULE:accept_clients(Socket, Server);
        quit -> gen_tcp:close(Socket)
    after 0 -> accept_clients(Socket, Server)
    end.

register_client(Socket, Server) ->
    socket_send(Socket, "Welcome to Recall. Connect with 'CONNECT name'."),
    {ok, N} = gen_tcp:recv(Socket, 0),
    case string:tokens(N, " \r\n") of
        ["CONNECT", Name] ->
            Client = #client{socket=Socket, name=Name, pid=self()},
            Server ! {'new client', Client},
            socket_send(Socket, "ok"),
            client_loop(Client, Server);
    
        _ ->
            gen_tcp:send(Socket, "That wasn't sensible, sorry."),
            gen_tcp:close(Socket)
    end.

client_loop(Client = #client{socket = Socket}, Server) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Recv} -> do_command(Socket, split_command(Recv));
        {error, _} -> Server ! {'lost client', Client}
    end,
    receive
        refresh -> ?MODULE:client_loop(Client, Server);
        quit -> gen_tcp:close(Socket)
    after 0 -> client_loop(Client, Server)
    end.

socket_send(Socket, Msg) -> gen_tcp:send(Socket, Msg ++ "\r\n").

split_command(CmdStr) ->
    Cmd = string:sub_word(CmdStr, 1),
    {Cmd, string:strip(CmdStr -- Cmd)}.

do_command(Socket, {"ECHO", Args}) ->
    socket_send(Socket, Args),
    socket_send(Socket, "ok");
do_command(Socket, {Cmd, _Args}) ->
    io:fwrite("--> Calling default handler for command ~s...~n", [Cmd]),
    socket_send(Socket, "ok").

start_mnesia() ->
    mnesia:create_schema([node()]),
    mnesia:start().
