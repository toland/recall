-module(recall).
-export([start/0, 
         start/1, 
         init/1, 
         loop/1,
         accept_clients/2, 
         register_client/2, 
         client_loop/2]).

-define(DEFAULT_PORT, 9900).

-record(session, {socket, accepter, clients}).
-record(client, {socket, name, pid}).


start()     -> start(?DEFAULT_PORT).
start(Port) -> spawn(?MODULE, start, [Port]).

    
init(Port) ->
    {ok, Socket} = gen_tcp:listen(Port, [{packet, 0}, {active, false}]),
    Accepter = spawn_link(?MODULE, accept_clients, [Socket, self()]),
	io:fwrite(standard_io, "--> Recall Server Started on port ~B...~n", [Port]),
    loop(#session{socket = Socket, accepter = Accepter, clients = []}).


loop(Session = #session{accepter = A, clients = Cs}) ->
    receive
        {'new client', Client} ->
            erlang:monitor(process, Client#client.pid),
            Cs1 = [Client|Cs],
            io:fwrite(user, "--> new connection from ~s\r\n", [Client#client.name]),
            loop(Session#session{clients = Cs1});

        {'DOWN', _, process, Pid, _Info} ->
            case lists:keysearch(Pid, #client.pid, Cs) of
                false -> loop(Session);
                {value, Client} -> 
                    self() ! {'lost client', Client},
                    loop(Session)
            end;

        {'lost client', Client} ->
            io:fwrite(user, "--> lost connection from ~s\r\n", [Client#client.name]),
            gen_tcp:close(Client#client.socket),
            loop(Session#session{clients = lists:delete(Client, Cs)});

        {message, Client, Msg} ->
            io:fwrite(user, "--> <~s> ~s\r\n", [Client#client.name, Msg]),
            loop(Session);

        refresh ->
            io:fwrite(standard_io, "--> Refreshing Recall server...", []),
            A ! refresh,
            lists:foreach(fun (#client{pid=CP}) -> CP ! refresh end, Cs),
            ?MODULE:loop(Session)
    end.


accept_clients(Socket, Server) ->
    {ok, Client} = gen_tcp:accept(Socket),
    spawn(?MODULE, register_client, [Client, Server]),
    receive
        refresh -> ?MODULE:accept_clients(Socket, Server)
    after 0 -> accept_clients(Socket, Server)
    end.

register_client(Socket, Server) ->
    gen_tcp:send(Socket, "Welcome to Recall. Connect with 'CONNECT name'.\r\n"),
    {ok, N} = gen_tcp:recv(Socket, 0),
    case string:tokens(N, " \r\n") of
        ["CONNECT", Name] ->
            Client = #client{socket=Socket, name=Name, pid=self()},
            Server ! {'new client', Client},
            client_loop(Client, Server);

        _ ->
            gen_tcp:send(Socket, "That wasn't sensible, sorry."),
            gen_tcp:close(Socket)
    end.

client_loop(Client, Server) ->
    case gen_tcp:recv(Client#client.socket, 0) of
        {ok, Recv} ->
            lists:foreach(fun (S) -> Server ! {message, Client, S} end,
                          string:tokens(Recv, "\r\n"));

        {error, _} ->
            Server ! {'lost client', Client}
    end,
    receive
        refresh -> ?MODULE:client_loop(Client, Server)
    after 0 -> client_loop(Client, Server)
    end.

